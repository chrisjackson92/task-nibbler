-- +goose Up
CREATE TABLE recurring_rules (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  rrule      TEXT        NOT NULL,   -- iCal RRULE string (e.g. FREQ=DAILY;INTERVAL=1)
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_recurring_rules_user ON recurring_rules (user_id);

-- +goose Down
DROP INDEX IF EXISTS idx_recurring_rules_user;
DROP TABLE IF EXISTS recurring_rules;
