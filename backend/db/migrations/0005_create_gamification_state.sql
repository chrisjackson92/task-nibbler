-- +goose Up
CREATE TABLE gamification_state (
  id                       UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                  UUID    NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  streak_count             INTEGER NOT NULL DEFAULT 0,
  last_active_date         DATE,                    -- UTC date of last task completion
  grace_used_at            DATE,                    -- UTC date grace was last used (1 per 7-day window)
  has_completed_first_task BOOLEAN NOT NULL DEFAULT FALSE,
  tree_health_score        INTEGER NOT NULL DEFAULT 50 CHECK (tree_health_score >= 0 AND tree_health_score <= 100),
  created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_gamification_user ON gamification_state (user_id);

-- +goose Down
DROP INDEX IF EXISTS idx_gamification_user;
DROP TABLE IF EXISTS gamification_state;
