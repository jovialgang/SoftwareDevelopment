package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"

	"mini-task-tracker/internal/models"
	"mini-task-tracker/internal/storage"
)

// TaskHandler содержит зависимости для работы с задачами.
type TaskHandler struct {
	storage *storage.MemoryTaskStorage
}

// NewTaskHandler создает новый TaskHandler.
func NewTaskHandler(storage *storage.MemoryTaskStorage) *TaskHandler {
	return &TaskHandler{storage: storage}
}

// createTaskRequest описывает тело запроса для создания задачи.
type createTaskRequest struct {
	Title       string  `json:"title"`
	Description *string `json:"description"`
	Status      *string `json:"status"`
}

// updateStatusRequest описывает тело запроса для обновления статуса.
type updateStatusRequest struct {
	Status string `json:"status"`
}

// errorResponse — стандартный ответ об ошибке.
type errorResponse struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

// messageResponse — простой ответ с сообщением.
type messageResponse struct {
	Message string `json:"message"`
}

// writeJSON отправляет JSON-ответ с заданным статусом.
func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// writeError отправляет стандартный JSON-ответ об ошибке.
func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, errorResponse{
		Code:    status,
		Message: msg,
	})
}

// parseTaskID извлекает и проверяет ID задачи из URL.
func parseTaskID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	idStr := chi.URLParam(r, "id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil || id <= 0 {
		writeError(w, http.StatusBadRequest, "invalid id")
		return 0, false
	}
	return id, true
}

// parseStatus проверяет корректность статуса.
func parseStatus(raw string) (models.TaskStatus, bool) {
	switch models.TaskStatus(raw) {
	case models.TaskStatusTodo, models.TaskStatusInProgress, models.TaskStatusDone:
		return models.TaskStatus(raw), true
	default:
		return "", false
	}
}

// ListTasks обрабатывает GET /tasks.
func (h *TaskHandler) ListTasks(w http.ResponseWriter, r *http.Request) {
	tasks := h.storage.GetAllTasks()
	writeJSON(w, http.StatusOK, tasks)
}

// CreateTask обрабатывает POST /tasks.
func (h *TaskHandler) CreateTask(w http.ResponseWriter, r *http.Request) {
	var req createTaskRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid JSON body")
		return
	}

	if req.Title == "" {
		writeError(w, http.StatusBadRequest, "title is required")
		return
	}

	// Значение по умолчанию — todo.
	status := models.TaskStatusTodo
	if req.Status != nil && *req.Status != "" {
		parsed, ok := parseStatus(*req.Status)
		if !ok {
			writeError(w, http.StatusBadRequest, "invalid status")
			return
		}
		status = parsed
	}

	task := h.storage.CreateTask(req.Title, req.Description, status)
	writeJSON(w, http.StatusCreated, task)
}

// GetTaskByID обрабатывает GET /tasks/{id}.
func (h *TaskHandler) GetTaskByID(w http.ResponseWriter, r *http.Request) {
	id, ok := parseTaskID(w, r)
	if !ok {
		return
	}

	task, found := h.storage.GetTaskByID(id)
	if !found {
		writeError(w, http.StatusNotFound, "task not found")
		return
	}

	writeJSON(w, http.StatusOK, task)
}

// UpdateTaskStatus обрабатывает PATCH /tasks/{id}/status.
func (h *TaskHandler) UpdateTaskStatus(w http.ResponseWriter, r *http.Request) {
	id, ok := parseTaskID(w, r)
	if !ok {
		return
	}

	var req updateStatusRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid JSON body")
		return
	}

	if req.Status == "" {
		writeError(w, http.StatusBadRequest, "status is required")
		return
	}

	status, valid := parseStatus(req.Status)
	if !valid {
		writeError(w, http.StatusBadRequest, "invalid status")
		return
	}

	task, found := h.storage.UpdateTaskStatus(id, status)
	if !found {
		writeError(w, http.StatusNotFound, "task not found")
		return
	}

	writeJSON(w, http.StatusOK, task)
}

// DeleteTask обрабатывает DELETE /tasks/{id}.
func (h *TaskHandler) DeleteTask(w http.ResponseWriter, r *http.Request) {
	id, ok := parseTaskID(w, r)
	if !ok {
		return
	}

	deleted := h.storage.DeleteTask(id)
	if !deleted {
		writeError(w, http.StatusNotFound, "task not found")
		return
	}

	writeJSON(w, http.StatusOK, messageResponse{
		Message: "task deleted",
	})
}

