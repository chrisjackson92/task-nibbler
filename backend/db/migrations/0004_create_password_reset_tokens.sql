-- +goose Up
CREATE TABLE password_reset_tokens (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash VARCHAR(64) NOT NULL UNIQUE, -- SHA-256 of the raw token in the email link
  expires_at TIMESTAMPTZ NOT NULL,        -- 1 hour TTL
  used_at    TIMESTAMPTZ,                 -- NULL = unused; NOT NULL = consumed
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_prt_token_hash ON password_reset_tokens (token_hash);
CREATE INDEX idx_prt_user_id    ON password_reset_tokens (user_id);

-- +goose Down
DROP INDEX IF EXISTS idx_prt_user_id;
DROP INDEX IF EXISTS idx_prt_token_hash;
DROP TABLE IF EXISTS password_reset_tokens;
