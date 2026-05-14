-- +goose Up
-- Create all PostgreSQL ENUM types used across the schema.
-- These must be created before any table that references them.

CREATE TYPE task_priority AS ENUM ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL');
CREATE TYPE task_type     AS ENUM ('ONE_TIME', 'RECURRING');
CREATE TYPE task_status   AS ENUM ('PENDING', 'COMPLETED', 'CANCELLED');
CREATE TYPE attachment_status AS ENUM ('PENDING', 'COMPLETE');
CREATE TYPE device_platform   AS ENUM ('ios', 'android');
CREATE TYPE badge_trigger_type AS ENUM (
  'FIRST_TASK',
  'STREAK_MILESTONE',
  'VOLUME_STREAK',
  'DAILY_VOLUME',
  'TREE_HEALTH'
);

-- +goose Down
DROP TYPE IF EXISTS badge_trigger_type;
DROP TYPE IF EXISTS device_platform;
DROP TYPE IF EXISTS attachment_status;
DROP TYPE IF EXISTS task_status;
DROP TYPE IF EXISTS task_type;
DROP TYPE IF EXISTS task_priority;
