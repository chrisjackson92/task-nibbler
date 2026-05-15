-- +goose Up
-- +goose StatementBegin

CREATE TABLE badges (
  id           VARCHAR(50) PRIMARY KEY,             -- e.g. 'STREAK_7', 'FIRST_NIBBLE'
  name         VARCHAR(100) NOT NULL,
  description  TEXT         NOT NULL,
  emoji        VARCHAR(10)  NOT NULL,
  trigger_type badge_trigger_type NOT NULL,
  created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP TABLE IF EXISTS badges;
-- +goose StatementEnd
