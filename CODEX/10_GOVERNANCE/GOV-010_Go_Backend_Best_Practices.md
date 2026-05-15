---
id: GOV-010
title: "Go Backend Best Practices — Task Nibbles"
type: reference
status: APPROVED
owner: architect
agents: [coder, tester]
tags: [coding, standards, governance, go, gin, sqlc, pgx, backend]
related: [GOV-003, GOV-004, GOV-006, BLU-003, AGT-002-BE]
created: 2026-05-15
updated: 2026-05-15
version: 1.0.0
---

> **BLUF:** Non-obvious, stack-specific best practices for the Go + Gin + sqlc + pgx + goose backend. Read this alongside GOV-003 (general coding standard). Items here are either Go-idiomatic requirements or common developer-agent failure modes observed in agentic codebases.

# Go Backend Best Practices

---

## 1. Error Handling

### 1.1 Always Wrap Errors with Context
Never return a bare error from a function. Callers need context.

```go
// ❌ Wrong — loses call-site context
return err

// ✅ Correct
return fmt.Errorf("task_repository.GetByID: %w", err)
```

### 1.2 Use `errors.Is` / `errors.As` for Typed Checks
```go
// ❌ Wrong — string comparison breaks with wrapping
if err.Error() == "no rows in result set" { ... }

// ✅ Correct
if errors.Is(err, pgx.ErrNoRows) { ... }
```

### 1.3 Map `pgx.ErrNoRows` to `apierr.ErrNotFound` in Repository Layer
The handler layer must never see a raw `pgx.ErrNoRows`. Repository functions are responsible for translating it:
```go
row, err := q.GetTask(ctx, id)
if errors.Is(err, pgx.ErrNoRows) {
    return nil, apierr.ErrNotFound
}
```

### 1.4 Gin: Use `c.Error()`, Never Bare `c.JSON` for Errors
All errors must flow through the Recovery middleware. This is a hard contract (CON-001 §5).
```go
// ❌ Wrong — bypasses error middleware, breaks envelope
c.JSON(http.StatusNotFound, gin.H{"error": "not found"})

// ✅ Correct
_ = c.Error(apierr.ErrNotFound)
return
```

---

## 2. Context Propagation

### 2.1 `ctx` is Always the First Parameter
Every function that touches I/O (DB, S3, email) must accept `context.Context` as the first argument. No exceptions.

### 2.2 Use `slog.InfoContext` / `slog.ErrorContext`, Not `slog.Info`
Context-aware logging allows future trace injection. The non-context variants are off-limits in application code (GOV-006).
```go
// ❌ Wrong
slog.Info("task created", "task_id", id)

// ✅ Correct
slog.InfoContext(ctx, "task created", "task_id", id)
```

### 2.3 Respect Context Cancellation in Loops
Long-running operations (cron jobs, batch queries) must check `ctx.Err()`:
```go
for _, task := range tasks {
    if ctx.Err() != nil {
        return ctx.Err()
    }
    // process task
}
```

---

## 3. Layer Contract (Strict — see BLU-003 §3)

| Layer | Can import | Cannot import |
|:------|:-----------|:--------------|
| Handler | Service interfaces, `gin`, `apierr` | `pgx`, `db.*`, direct repo calls |
| Service | Repository interfaces, domain types | `gin.Context`, HTTP status codes |
| Repository | `db.*` (sqlc), `pgx`, `apierr` | `gin`, service types |

**Never cross layers.** If a handler needs data that requires two service calls, that orchestration belongs in a new service method — not in the handler.

---

## 4. sqlc Patterns

### 4.1 Never Modify Generated Files
`internal/db/*.go` is auto-generated. Any change is wiped on the next `sqlc generate`. Write all custom logic in the repository layer.

### 4.2 Extend `gamification.sql` — Don't Create a New File
All gamification queries live in `db/queries/gamification.sql`. Append to existing files by domain; don't create a `gamification2.sql`.

### 4.3 Use Named Parameters in sqlc Comments
```sql
-- name: GetTaskByID :one
SELECT * FROM tasks WHERE id = $1 AND user_id = $2 LIMIT 1;
```
The `:one`, `:many`, `:exec` directives control the generated return type. Use `:execrows` when you need the affected row count.

### 4.4 Nullable Fields Use `pgtype` or Pointer Types
sqlc maps nullable columns to `pgtype.Text`, `pgtype.Timestamptz`, etc. When assigning from Go:
```go
// For a nullable timestamptz column:
params.CancelledAt = pgtype.Timestamptz{Time: time.Now().UTC(), Valid: true}

// To clear it (set NULL):
params.CancelledAt = pgtype.Timestamptz{Valid: false}
```

---

## 5. pgx / Database Patterns

### 5.1 Use `pgxpool` — Never a Single Connection
The pool is initialised in `main.go` and injected via dependency injection. Never call `pgx.Connect()` directly in application code.

### 5.2 Transactions: Use `pgxpool.BeginTx`, Defer Rollback
```go
tx, err := pool.BeginTx(ctx, pgx.TxOptions{})
if err != nil {
    return fmt.Errorf("begin tx: %w", err)
}
defer tx.Rollback(ctx) // no-op if already committed

// ... do work ...

return tx.Commit(ctx)
```
The deferred `Rollback` is safe to call after a successful `Commit` — pgx ignores it.

### 5.3 Avoid `SELECT *` in Hand-Written Queries
sqlc generates type-safe structs based on explicit column lists. `SELECT *` breaks when columns are added. Always list columns explicitly.

---

## 6. Interface Design

### 6.1 Accept Interfaces, Return Concrete Types
```go
// ✅ Service accepts a repository interface (testable)
type TaskService struct {
    repo TaskRepository  // interface
}

// ✅ Constructor returns concrete struct (not interface)
func NewTaskService(repo TaskRepository) *TaskService { ... }
```

### 6.2 Define Interfaces in the Consumer Package
The `TaskRepository` interface lives in `internal/services/`, not in `internal/repositories/`. This avoids circular imports and follows Go convention.

### 6.3 Keep Interfaces Small
One or two methods per interface is the Go ideal. If a repository interface has 15 methods, consider splitting it.

---

## 7. Testing

### 7.1 Table-Driven Tests Are Mandatory for Handler/Service Logic
```go
tests := []struct {
    name       string
    input      CreateTaskRequest
    wantStatus int
}{
    {"missing title", CreateTaskRequest{}, http.StatusUnprocessableEntity},
    {"valid request", CreateTaskRequest{Title: "Buy milk"}, http.StatusCreated},
}
for _, tt := range tests {
    t.Run(tt.name, func(t *testing.T) { ... })
}
```

### 7.2 Mock Repositories, Not the Database
Integration tests that hit a real PostgreSQL are slow and fragile in CI. Use interface-based mocks for service unit tests. Only repository-layer tests use a real DB (test containers or a local test DB).

### 7.3 Test File Naming
Test files live **next to** the file they test, with the `_test` suffix:
```
internal/services/task_service.go
internal/services/task_service_test.go   ✅
internal/services/tests/task_service_test.go  ❌ (wrong — separate dir)
```

### 7.4 Use `t.Cleanup` Instead of `defer` in Tests
`t.Cleanup` runs after every subtest, not just after the parent function returns:
```go
t.Cleanup(func() { db.Exec("DELETE FROM tasks") })
```

---

## 8. Gin / HTTP Patterns

### 8.1 Bind and Validate in One Step
```go
var req CreateTaskRequest
if err := c.ShouldBindJSON(&req); err != nil {
    _ = c.Error(apierr.NewValidationError(err))
    return
}
```
Use `ShouldBindJSON` (returns error) over `BindJSON` (calls `c.AbortWithError` internally, which breaks middleware flow).

### 8.2 Extract User ID from Context, Never from Request Body
The JWT middleware sets `userID` on the Gin context. Handlers read it:
```go
userID := c.MustGet("userID").(uuid.UUID)
```
Never trust a `user_id` field in the request body — it's a security vulnerability.

### 8.3 Use `c.Param` for Path Variables, `c.Query` for Query Params
```go
taskID := c.Param("id")         // /tasks/:id
status  := c.Query("status")    // ?status=PENDING
```

### 8.4 Always `return` After `c.Error()`
`c.Error()` does not stop handler execution. Always return immediately after:
```go
_ = c.Error(apierr.ErrNotFound)
return  // ← REQUIRED
```

---

## 9. Goroutines and Concurrency

### 9.1 Cron Jobs Must Not Share Mutable State
Each cron job execution should be stateless — read from DB, compute, write to DB. Never store intermediate results in struct fields shared between runs.

### 9.2 Graceful Shutdown
The `main.go` must listen for `SIGTERM`/`SIGINT` and give in-flight requests time to complete:
```go
quit := make(chan os.Signal, 1)
signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
<-quit
ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
defer cancel()
srv.Shutdown(ctx)
```
Fly.io sends `SIGTERM` before killing the machine. Without this, in-flight DB writes are lost.

---

## 10. Package & Project Conventions

| Convention | Rule |
|:-----------|:-----|
| Package names | Lowercase, single word, no underscores: `apierr` not `api_error` |
| File names | Snake case: `task_service.go`, `auth_handler.go` |
| `init()` | Forbidden in application code — initialise in `main.go` or constructors |
| `panic()` | Forbidden outside `main.go` startup checks |
| `log.Fatal` | Only in `main.go` startup — nowhere else |
| Constants | Use `iota` for sequential, typed constants only; avoid bare `const = 1` magic numbers |

---

> *These practices are standing rules for all backend sprints. Violations found at audit become DEF- reports.*
