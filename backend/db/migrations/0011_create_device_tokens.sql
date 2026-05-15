-- +goose Up
-- +goose StatementBegin

-- device_tokens: pre-provisioned for V2 FCM push notifications.
-- No API endpoints in MVP — registered via POST /notifications/token in V2.
CREATE TABLE device_tokens (
  id         UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token      VARCHAR(500)    NOT NULL,
  platform   device_platform NOT NULL,
  created_at TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

  CONSTRAINT uq_device_token UNIQUE (user_id, token)    -- prevent duplicate registrations
);

CREATE INDEX idx_device_tokens_user ON device_tokens (user_id);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP TABLE IF EXISTS device_tokens;
-- +goose StatementEnd
