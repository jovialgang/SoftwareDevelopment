package main

import (
	"log"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	httpSwagger "github.com/swaggo/http-swagger"

	"mini-task-tracker/internal/handlers"
	appmetrics "mini-task-tracker/internal/metrics"
	"mini-task-tracker/internal/storage"
)

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
		routePattern := chi.RouteContext(r.Context()).RoutePattern()
		if routePattern == "" {
			routePattern = r.URL.Path
		}

		duration := time.Since(start).Seconds()
		statusCode := strconv.Itoa(ww.Status())

		appmetrics.HTTPRequestsTotal.
			WithLabelValues(r.Method, routePattern, statusCode).Inc()
		appmetrics.HTTPRequestDuration.
			WithLabelValues(r.Method, routePattern).Observe(duration)
	})
}

func main() {
	r := chi.NewRouter()

	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
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
