-- +goose Up
CREATE TABLE tasks (
  id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  recurring_rule_id  UUID        REFERENCES recurring_rules(id) ON DELETE SET NULL,
  title              TEXT        NOT NULL CHECK (char_length(title) <= 200),
  description        TEXT        CHECK (char_length(description) <= 2000),
  address            TEXT        CHECK (char_length(address) <= 500),
  priority           task_priority NOT NULL DEFAULT 'MEDIUM',
  task_type          task_type   NOT NULL DEFAULT 'ONE_TIME',
  status             task_status NOT NULL DEFAULT 'PENDING',
  sort_order         INTEGER     NOT NULL DEFAULT 0,
  is_detached        BOOLEAN     NOT NULL DEFAULT FALSE,  -- TRUE when a recurring instance was individually edited
  start_at           TIMESTAMPTZ,
  end_at             TIMESTAMPTZ,
  completed_at       TIMESTAMPTZ,
  cancelled_at       TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Efficient list queries scoped to user, ordered by sort_order
CREATE INDEX idx_tasks_user_sort ON tasks (user_id, sort_order);
-- Status filter queries
CREATE INDEX idx_tasks_user_status ON tasks (user_id, status);
-- Overdue detection: pending tasks with end_at in the past
CREATE INDEX idx_tasks_user_end_at ON tasks (user_id, end_at) WHERE status = 'PENDING';

-- +goose Down
DROP INDEX IF EXISTS idx_tasks_user_end_at;
DROP INDEX IF EXISTS idx_tasks_user_status;
DROP INDEX IF EXISTS idx_tasks_user_sort;
DROP TABLE IF EXISTS tasks;
