package metrics

import "github.com/prometheus/client_golang/prometheus"

// HTTP-метрики.
var (
	// HTTPRequestsTotal — общее число HTTP-запросов по методу, пути и коду ответа.
	HTTPRequestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Total number of HTTP requests by method, path and status code.",
		},
		[]string{"method", "path", "status_code"},
	)

	// HTTPRequestDuration — гистограмма времени ответа по методу и пути.
	HTTPRequestDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "HTTP request duration in seconds.",
			Buckets: []float64{.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 10},
		},
		[]string{"method", "path"},
	)

	// HTTPRequestsInFlight — число запросов, обрабатываемых прямо сейчас.
	HTTPRequestsInFlight = prometheus.NewGauge(
		prometheus.GaugeOpts{
			Name: "http_requests_in_flight",
			Help: "Current number of HTTP requests being processed.",
		},
	)
)

// Продуктовые (бизнес) метрики.
var (
	// TasksTotal — текущее число задач по статусу (todo / in_progress / done).
	TasksTotal = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "tasks_total",
			Help: "Current number of tasks by status.",
		},
		[]string{"status"},
	)

	// TasksCreatedTotal — сколько задач создано за всё время.
	TasksCreatedTotal = prometheus.NewCounter(
		prometheus.CounterOpts{
			Name: "tasks_created_total",
			Help: "Total number of tasks ever created.",
		},
	)

	// TasksDeletedTotal — сколько задач удалено за всё время.
	TasksDeletedTotal = prometheus.NewCounter(
		prometheus.CounterOpts{
			Name: "tasks_deleted_total",
			Help: "Total number of tasks ever deleted.",
		},
	)

	// TasksStatusChangesTotal — счётчик переходов между статусами задач.
	TasksStatusChangesTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "tasks_status_changes_total",
			Help: "Total number of task status transitions.",
		},
		[]string{"from", "to"},
	)
)

func init() {
	prometheus.MustRegister(
		HTTPRequestsTotal,
		HTTPRequestDuration,
		HTTPRequestsInFlight,
		TasksTotal,
		TasksCreatedTotal,
		TasksDeletedTotal,
		TasksStatusChangesTotal,
	)

	// Инициализируем gauges нулями, чтобы все статусы сразу были видны в Grafana.
	for _, status := range []string{"todo", "in_progress", "done"} {
		TasksTotal.WithLabelValues(status).Set(0)
	}
}
