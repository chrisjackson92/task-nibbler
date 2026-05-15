-- +goose Up
-- +goose StatementBegin

-- Create attachment_status enum (only if not already created in enums migration)
-- The enum was defined in 0001_create_enums.sql; no need to recreate here.

CREATE TABLE task_attachments (
  id                UUID              PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id           UUID              NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  user_id           UUID              NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status            attachment_status NOT NULL DEFAULT 'PENDING',
  s3_key            VARCHAR(500)      NOT NULL,       -- full S3 key: {user_id}/{task_id}/{attachment_id}.{ext}
  mime_type         VARCHAR(100)      NOT NULL,
  size_bytes        BIGINT,                            -- declared by client; validated at pre-register
  original_filename VARCHAR(255)      NOT NULL,
  created_at        TIMESTAMPTZ       NOT NULL DEFAULT NOW(),
  confirmed_at      TIMESTAMPTZ                        -- set when status → COMPLETE
);

-- Optimised for listing COMPLETE attachments per task (GET /tasks/:id/attachments)
CREATE INDEX idx_attachments_task_status ON task_attachments (task_id, status) WHERE status = 'COMPLETE';
-- Optimised for nightly cleanup cron (DELETE WHERE PENDING AND created_at < NOW()-1h)
CREATE INDEX idx_attachments_cleanup     ON task_attachments (status, created_at) WHERE status = 'PENDING';
-- Optimised for cascade deletes by user
CREATE INDEX idx_attachments_user        ON task_attachments (user_id);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP TABLE IF EXISTS task_attachments;
-- +goose StatementEnd
