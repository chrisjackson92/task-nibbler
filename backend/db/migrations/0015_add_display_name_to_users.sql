-- +goose Up
-- Add display_name to users (SPR-009-MB)
ALTER TABLE users ADD COLUMN IF NOT EXISTS display_name TEXT;

-- +goose Down
ALTER TABLE users DROP COLUMN IF EXISTS display_name;
