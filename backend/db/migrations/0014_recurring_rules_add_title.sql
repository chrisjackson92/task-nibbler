-- +goose Up
-- +goose StatementBegin
-- Add title column to recurring_rules.
-- Required because the nightly expansion cron creates concrete task instances from the rule
-- and must populate tasks.title correctly (FindIng #1 — AUD-006-BE).
-- DEFAULT '' allows safe ADD COLUMN without a two-step migration per GOV-010 §4.5.
ALTER TABLE recurring_rules ADD COLUMN title TEXT NOT NULL DEFAULT '';

-- Optional backfill: copy title from the first concrete task instance for each rule.
-- Safe for both empty and populated tables.
UPDATE recurring_rules rr
   SET title = (
       SELECT title
       FROM tasks
       WHERE recurring_rule_id = rr.id
       ORDER BY created_at
       LIMIT 1
   )
WHERE EXISTS (
    SELECT 1 FROM tasks WHERE recurring_rule_id = rr.id
);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
ALTER TABLE recurring_rules DROP COLUMN IF EXISTS title;
-- +goose StatementEnd
