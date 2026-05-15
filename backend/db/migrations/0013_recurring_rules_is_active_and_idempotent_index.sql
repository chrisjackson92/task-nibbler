-- +goose Up

-- Add is_active column to recurring_rules (missing from 0006 baseline per BLU-002 §3.4)
ALTER TABLE recurring_rules ADD COLUMN is_active BOOLEAN NOT NULL DEFAULT TRUE;

-- Partial index: nightly cron queries WHERE is_active = TRUE — index prunes inactive rules
CREATE INDEX idx_recurring_rules_is_active ON recurring_rules (is_active) WHERE is_active = TRUE;

-- Unique constraint for idempotent nightly expansion (TRB-005/TRB-006 — AUD-008-OPS).
--
-- Two gotchas fixed here:
--   1. DATE(timestamptz) is STABLE (session-timezone-dependent) — rejected by PG in index expressions.
--      Fix: use AT TIME ZONE 'UTC' on the timestamptz; the at_time_zone(timestamptz, interval)
--      variant with INTERVAL '0' is IMMUTABLE (pure arithmetic — no timezone lookup).
--   2. The PostgreSQL :: cast operator is mis-tokenised inside goose StatementBegin blocks.
--      Fix: use ANSI CAST(... AS date) syntax + remove StatementBegin so goose splits on ;
--
CREATE UNIQUE INDEX uq_recurring_instance
  ON tasks (
    recurring_rule_id,
    CAST(COALESCE(start_at, created_at) AT TIME ZONE INTERVAL '0' AS date)
  )
  WHERE recurring_rule_id IS NOT NULL AND is_detached = FALSE;

-- +goose Down
DROP INDEX IF EXISTS uq_recurring_instance;
DROP INDEX IF EXISTS idx_recurring_rules_is_active;
ALTER TABLE recurring_rules DROP COLUMN IF EXISTS is_active;
