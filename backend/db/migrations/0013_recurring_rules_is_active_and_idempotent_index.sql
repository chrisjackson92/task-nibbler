-- +goose Up
-- +goose StatementBegin

-- Add is_active column to recurring_rules (missing from 0006 baseline per BLU-002 §3.4)
ALTER TABLE recurring_rules ADD COLUMN is_active BOOLEAN NOT NULL DEFAULT TRUE;

-- Partial index: nightly cron queries WHERE is_active = TRUE — index prunes inactive rules
CREATE INDEX idx_recurring_rules_is_active ON recurring_rules (is_active) WHERE is_active = TRUE;

-- Unique constraint for idempotent nightly expansion:
-- One concrete task instance per rule per calendar day (for non-detached instances).
-- INSERT ... ON CONFLICT DO NOTHING uses this index to skip duplicates.
CREATE UNIQUE INDEX uq_recurring_instance
  ON tasks (recurring_rule_id, DATE(COALESCE(start_at, created_at)))
  WHERE recurring_rule_id IS NOT NULL AND is_detached = FALSE;

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP INDEX IF EXISTS uq_recurring_instance;
DROP INDEX IF EXISTS idx_recurring_rules_is_active;
ALTER TABLE recurring_rules DROP COLUMN IF EXISTS is_active;
-- +goose StatementEnd
