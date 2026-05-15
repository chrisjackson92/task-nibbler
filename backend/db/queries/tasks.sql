-- name: CreateTask :one
INSERT INTO tasks (
  user_id, recurring_rule_id, title, description, address,
  priority, task_type, sort_order, start_at, end_at
) VALUES (
  $1, $2, $3, $4, $5, $6, $7, $8, $9, $10
)
RETURNING *;

-- name: GetTaskByID :one
SELECT * FROM tasks
WHERE id = $1 AND user_id = $2
LIMIT 1;

-- name: GetMaxSortOrder :one
SELECT COALESCE(MAX(sort_order), -1) AS max_sort_order
FROM tasks
WHERE user_id = $1;

-- name: ListTasks :many
SELECT * FROM tasks
WHERE user_id = $1
  AND ($2::task_status IS NULL OR status = $2)
  AND ($3::task_priority IS NULL OR priority = $3)
  AND ($4::task_type IS NULL OR task_type = $4)
  AND ($5::timestamptz IS NULL OR end_at >= $5)
  AND ($6::timestamptz IS NULL OR end_at <= $6)
  AND ($7::text IS NULL OR (
    to_tsvector('english', title || ' ' || COALESCE(description, '')) @@ plainto_tsquery('english', $7)
  ))
ORDER BY
  CASE WHEN $8 = 'due_date'    AND $9 = 'asc'  THEN end_at     END ASC  NULLS LAST,
  CASE WHEN $8 = 'due_date'    AND $9 = 'desc' THEN end_at     END DESC NULLS LAST,
  CASE WHEN $8 = 'priority'    AND $9 = 'asc'  THEN priority::text END ASC,
  CASE WHEN $8 = 'priority'    AND $9 = 'desc' THEN priority::text END DESC,
  CASE WHEN $8 = 'created_at'  AND $9 = 'asc'  THEN created_at END ASC,
  CASE WHEN $8 = 'created_at'  AND $9 = 'desc' THEN created_at END DESC,
  sort_order ASC  -- default / fallback
LIMIT $10 OFFSET $11;

-- name: CountTasks :one
SELECT COUNT(*) FROM tasks
WHERE user_id = $1
  AND ($2::task_status IS NULL OR status = $2)
  AND ($3::task_priority IS NULL OR priority = $3)
  AND ($4::task_type IS NULL OR task_type = $4)
  AND ($5::timestamptz IS NULL OR end_at >= $5)
  AND ($6::timestamptz IS NULL OR end_at <= $6)
  AND ($7::text IS NULL OR (
    to_tsvector('english', title || ' ' || COALESCE(description, '')) @@ plainto_tsquery('english', $7)
  ));

-- name: UpdateTask :one
UPDATE tasks SET
  title       = COALESCE(sqlc.narg('title'),       title),
  description = COALESCE(sqlc.narg('description'), description),
  address     = COALESCE(sqlc.narg('address'),     address),
  priority    = COALESCE(sqlc.narg('priority'),    priority),
  task_type   = COALESCE(sqlc.narg('task_type'),   task_type),
  status      = COALESCE(sqlc.narg('status'),      status),
  sort_order  = COALESCE(sqlc.narg('sort_order'),  sort_order),
  start_at    = COALESCE(sqlc.narg('start_at'),    start_at),
  end_at      = COALESCE(sqlc.narg('end_at'),      end_at),
  cancelled_at = COALESCE(sqlc.narg('cancelled_at'), cancelled_at),
  updated_at  = NOW()
WHERE id = $1 AND user_id = $2
RETURNING *;

-- name: CompleteTask :one
UPDATE tasks SET
  status       = 'COMPLETED',
  completed_at = NOW(),
  updated_at   = NOW()
WHERE id = $1 AND user_id = $2 AND status = 'PENDING'
RETURNING *;

-- name: DeleteTask :exec
DELETE FROM tasks
WHERE id = $1 AND user_id = $2;

-- name: UpdateTaskSortOrder :exec
UPDATE tasks SET
  sort_order = $1,
  updated_at = NOW()
WHERE id = $2 AND user_id = $3;
