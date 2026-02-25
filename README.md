# Mini Task Tracker (учебный API-first проект)

![imgs/img.png](imgs/img.png)

## Описание проекта

Mini Task Tracker — это **максимально простой учебный сервис** для управления задачами.

Основные цели проекта:

- **API-first подход**: сначала проектируется OpenAPI-спецификация (`openapi.yaml`), потом пишется код.
- **OpenAPI и Swagger UI**.

Сервис умеет:

- Создавать задачи
- Получать список задач
- Получать задачу по ID
- Менять статус задачи
- Удалять задачу

Данные хранятся **в памяти** (in-memory), без БД.

---

## Стек

- Go 1.22+
- `net/http`
- `github.com/go-chi/chi/v5`
- `github.com/swaggo/http-swagger`
- Без БД, без авторизации, без DI, без «production» оверхеда

---

## Структура проекта

```text
.
├── openapi.yaml
├── README.md
├── go.mod
├── cmd/
│   └── server/
│       └── main.go
├── internal/
│   ├── handlers/
│   │   └── tasks.go
│   ├── models/
│   │   └── task.go
│   └── storage/
│       └── memory.go
└── Makefile
```

---

## Как запустить

1. Установить зависимости (из корня проекта):

```bash
go mod tidy
```

2. Запустить сервер:

```bash
go run ./cmd/server
# или
go run cmd/server/main.go
```

Сервер поднимется на `http://localhost:8080`.

---

## Как открыть Swagger UI

После запуска сервера в браузере:

```text
http://localhost:8080/swagger
```

Файл спецификации `openapi.yaml` также доступен по адресу:

```text
http://localhost:8080/openapi.yaml
```

Swagger UI автоматически использует этот файл как источник схемы.

---

## Модель данных Task

```json
{
  "id": 1,
  "title": "Buy groceries",
  "description": "Milk, bread, eggs",
  "status": "todo",
  "created_at": "2026-02-25T10:00:00Z"
}
```

Поля:

- `id` — целое число (integer), генерируется сервером
- `title` — строка, **обязательное** поле
- `description` — строка, **необязательное** поле
- `status` — строка, одно из значений: `todo`, `in_progress`, `done`
- `created_at` — строка в формате datetime (RFC3339, UTC)

---

## Примеры curl-запросов

Все запросы выполняются к `http://localhost:8080`.

### 1. Создание задачи (POST /tasks)

```bash
curl -X POST http://localhost:8080/tasks \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Buy groceries",
    "description": "Milk, bread, eggs",
    "status": "todo"
  }'
```

Пример ответа (`201 Created`):

```json
{
  "id": 1,
  "title": "Buy groceries",
  "description": "Milk, bread, eggs",
  "status": "todo",
  "created_at": "2026-02-25T10:00:00Z"
}
```

Если не передать `status`, по умолчанию будет `todo`.

---

### 2. Получение списка задач (GET /tasks)

```bash
curl http://localhost:8080/tasks
```

Пример ответа (`200 OK`):

```json
[
  {
    "id": 1,
    "title": "Buy groceries",
    "description": "Milk, bread, eggs",
    "status": "todo",
    "created_at": "2026-02-25T10:00:00Z"
  },
  {
    "id": 2,
    "title": "Finish lab work",
    "status": "in_progress",
    "created_at": "2026-02-25T11:00:00Z"
  }
]
```

---

### 3. Получение задачи по ID (GET /tasks/{id})

```bash
curl http://localhost:8080/tasks/1
```

Пример ответа (`200 OK`):

```json
{
  "id": 1,
  "title": "Buy groceries",
  "description": "Milk, bread, eggs",
  "status": "todo",
  "created_at": "2026-02-25T10:00:00Z"
}
```

Если ID некорректен или задача не найдена:

```json
{
  "code": 404,
  "message": "task not found"
}
```

---

### 4. Изменение статуса задачи (PATCH /tasks/{id}/status)

```bash
curl -X PATCH http://localhost:8080/tasks/1/status \
  -H "Content-Type: application/json" \
  -d '{
    "status": "done"
  }'
```

Пример ответа (`200 OK`):

```json
{
  "id": 1,
  "title": "Buy groceries",
  "description": "Milk, bread, eggs",
  "status": "done",
  "created_at": "2026-02-25T10:00:00Z"
}
```

Если передан неправильный статус:

```json
{
  "code": 400,
  "message": "invalid status"
}
```

---

### 5. Удаление задачи (DELETE /tasks/{id})

```bash
curl -X DELETE http://localhost:8080/tasks/1
```

Пример ответа (`200 OK`):

```json
{
  "message": "task deleted"
}
```

Если задача не найдена:

```json
{
  "code": 404,
  "message": "task not found"
}
```

---

## Примеры JSON-ответов об ошибках

### Неверный ID

```json
{
  "code": 400,
  "message": "invalid id"
}
```

### Отсутствует обязательное поле `title`

```json
{
  "code": 400,
  "message": "title is required"
}
```

### Неверный статус

```json
{
  "code": 400,
  "message": "invalid status"
}
```

---

## Дальнейшее развитие (observability)

Поверх этого простого сервиса легко добавить:

- логирование запросов/ответов
- метрики (Prometheus)
- трассировку (OpenTelemetry)
- health-checkи и т.п.

Проект специально сделан простым и понятным, чтобы служить базой для лабораторных работ.

