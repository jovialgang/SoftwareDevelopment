package storage

import (
	"sync"
	"time"

	"mini-task-tracker/internal/models"
)

// MemoryTaskStorage — простейшее хранилище задач в памяти.
type MemoryTaskStorage struct {
	mu     sync.RWMutex
	tasks  map[int64]*models.Task
	nextID int64
}

// NewMemoryTaskStorage создает новое in-memory хранилище.
func NewMemoryTaskStorage() *MemoryTaskStorage {
	return &MemoryTaskStorage{
		tasks:  make(map[int64]*models.Task),
		nextID: 1,
	}
}

// CreateTask создает новую задачу и возвращает ее.
func (s *MemoryTaskStorage) CreateTask(title string, description *string, status models.TaskStatus) *models.Task {
	s.mu.Lock()
	defer s.mu.Unlock()

	id := s.nextID
	s.nextID++

	task := &models.Task{
		ID:          id,
		Title:       title,
		Description: description,
		Status:      status,
		CreatedAt:   time.Now().UTC().Format(time.RFC3339),
	}

	s.tasks[id] = task
	return task
}

// GetAllTasks возвращает список всех задач.
func (s *MemoryTaskStorage) GetAllTasks() []*models.Task {
	s.mu.RLock()
	defer s.mu.RUnlock()

	result := make([]*models.Task, 0, len(s.tasks))
	for _, t := range s.tasks {
		result = append(result, t)
	}
	return result
}

// GetTaskByID возвращает задачу по ID.
func (s *MemoryTaskStorage) GetTaskByID(id int64) (*models.Task, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	task, ok := s.tasks[id]
	return task, ok
}

// UpdateTaskStatus обновляет статус задачи по ID.
func (s *MemoryTaskStorage) UpdateTaskStatus(id int64, status models.TaskStatus) (*models.Task, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()

	task, ok := s.tasks[id]
	if !ok {
		return nil, false
	}

	task.Status = status
	return task, true
}

// DeleteTask удаляет задачу по ID.
func (s *MemoryTaskStorage) DeleteTask(id int64) bool {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.tasks[id]; !ok {
		return false
	}

	delete(s.tasks, id)
	return true
}

