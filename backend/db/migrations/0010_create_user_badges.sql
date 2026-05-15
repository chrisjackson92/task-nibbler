-- +goose Up
-- +goose StatementBegin

CREATE TABLE user_badges (
  id        UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id   UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  badge_id  VARCHAR(50) NOT NULL REFERENCES badges(id) ON DELETE CASCADE,
  earned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT uq_user_badge UNIQUE (user_id, badge_id)    -- idempotent: award once only
);

CREATE INDEX idx_user_badges_user ON user_badges (user_id, earned_at DESC);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP TABLE IF EXISTS user_badges;
-- +goose StatementEnd
