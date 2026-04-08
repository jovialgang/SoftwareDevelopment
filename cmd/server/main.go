package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	httpSwagger "github.com/swaggo/http-swagger"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"

	"mini-task-tracker/internal/handlers"
	appmetrics "mini-task-tracker/internal/metrics"
	"mini-task-tracker/internal/storage"
	"mini-task-tracker/internal/telemetry"
)

func routePatternFromRequest(r *http.Request) string {
	routeCtx := chi.RouteContext(r.Context())
	if routeCtx != nil {
		if pattern := routeCtx.RoutePattern(); pattern != "" {
			return pattern
		}
	}
	return r.URL.Path
}

// metricsMiddleware перехватывает каждый запрос и обновляет Prometheus-метрики.
// Паттерн маршрута читается ПОСЛЕ выполнения хендлера, когда chi уже проставил
// RoutePattern в контекст — это исключает cardinality explosion по /tasks/1, /tasks/2 и т.д.
func metricsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		appmetrics.HTTPRequestsInFlight.Inc()
		defer appmetrics.HTTPRequestsInFlight.Dec()

		// WrapResponseWriter позволяет прочитать статус-код после отправки ответа.
		ww := middleware.NewWrapResponseWriter(w, r.ProtoMajor)
		next.ServeHTTP(ww, r)

		// Читаем паттерн маршрута из chi-контекста (например, "/tasks/{id}").
		routePattern := routePatternFromRequest(r)

		duration := time.Since(start).Seconds()
		statusCode := strconv.Itoa(ww.Status())

		appmetrics.HTTPRequestsTotal.
			WithLabelValues(r.Method, routePattern, statusCode).Inc()
		appmetrics.HTTPRequestDuration.
			WithLabelValues(r.Method, routePattern).Observe(duration)
	})
}

// tracingMiddleware создает span на каждый HTTP-запрос.
func tracingMiddleware(next http.Handler) http.Handler {
	tracer := otel.Tracer("mini-task-tracker/http")

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		spanName := r.Method + " " + r.URL.Path
		ctx, span := tracer.Start(r.Context(), spanName, trace.WithAttributes(
			attribute.String("http.method", r.Method),
			attribute.String("url.path", r.URL.Path),
		))

		ww := middleware.NewWrapResponseWriter(w, r.ProtoMajor)
		next.ServeHTTP(ww, r.WithContext(ctx))

		routePattern := routePatternFromRequest(r)

		statusCode := ww.Status()
		span.SetAttributes(
			attribute.String("http.route", routePattern),
			attribute.Int("http.status_code", statusCode),
		)

		if statusCode >= 500 {
			span.SetStatus(codes.Error, "internal server error")
		}
		span.End()
	})
}

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	otelEndpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if otelEndpoint == "" {
		otelEndpoint = "127.0.0.1:14317"
	}

	shutdownTracing, err := telemetry.InitTracing(ctx, "mini-task-tracker", otelEndpoint)
	if err != nil {
		log.Fatalf("failed to init tracing: %v", err)
	}
	defer func() {
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := shutdownTracing(shutdownCtx); err != nil {
			log.Printf("failed to shutdown tracing: %v", err)
		}
	}()

	r := chi.NewRouter()

	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(tracingMiddleware)
	r.Use(metricsMiddleware)

	// Инициализируем хранилище и обработчики.
	taskStorage := storage.NewMemoryTaskStorage()
	taskHandler := handlers.NewTaskHandler(taskStorage)

	// Prometheus-метрики.
	r.Handle("/metrics", promhttp.Handler())

	// OpenAPI-спецификация и Swagger UI.
	r.Get("/openapi.yaml", func(w http.ResponseWriter, r *http.Request) {
		http.ServeFile(w, r, "openapi.yaml")
	})
	r.Get("/swagger", func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "/swagger/index.html", http.StatusMovedPermanently)
	})
	r.Get("/swagger/*", httpSwagger.Handler(
		httpSwagger.URL("/openapi.yaml"),
	))

	// Роуты задач.
	r.Route("/tasks", func(r chi.Router) {
		r.Get("/", taskHandler.ListTasks)
		r.Post("/", taskHandler.CreateTask)

		r.Route("/{id}", func(r chi.Router) {
			r.Get("/", taskHandler.GetTaskByID)
			r.Patch("/status", taskHandler.UpdateTaskStatus)
			r.Delete("/", taskHandler.DeleteTask)
		})
	})

	log.Println("Server is running on http://localhost:8080")
	log.Println("Metrics available at http://localhost:8080/metrics")
	if err := http.ListenAndServe(":8080", r); err != nil {
		log.Fatal(err)
	}
}
