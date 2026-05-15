-- +goose Up
CREATE TABLE users (
  id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  email         VARCHAR(320) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,               -- bcrypt hash (cost 12)
  timezone      VARCHAR(64)  NOT NULL DEFAULT 'UTC', -- IANA timezone string
  created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users (email);

-- +goose Down
DROP INDEX IF EXISTS idx_users_email;
DROP TABLE IF EXISTS users;
