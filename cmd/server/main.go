package main

import (
	"log"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	httpSwagger "github.com/swaggo/http-swagger"

	"mini-task-tracker/internal/handlers"
	"mini-task-tracker/internal/storage"
)

func main() {
	// Создаем роутер chi.
	r := chi.NewRouter()

	// Простейшие middleware для логирования и восстановления после паник.
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)

	// Инициализируем in-memory хранилище и обработчики.
	taskStorage := storage.NewMemoryTaskStorage()
	taskHandler := handlers.NewTaskHandler(taskStorage)

	// Раздача OpenAPI спецификации как файла.
	r.Get("/openapi.yaml", func(w http.ResponseWriter, r *http.Request) {
		http.ServeFile(w, r, "openapi.yaml")
	})

	// Swagger UI, который использует наш openapi.yaml.
	r.Get("/swagger", func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "/swagger/index.html", http.StatusMovedPermanently)
	})
	r.Get("/swagger/*", httpSwagger.Handler(
		httpSwagger.URL("/openapi.yaml"),
	))

	// Роуты для работы с задачами.
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
	if err := http.ListenAndServe(":8080", r); err != nil {
		log.Fatal(err)
	}
}
