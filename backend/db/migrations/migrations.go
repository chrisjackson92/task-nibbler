// Package migrations embeds all goose SQL migration files into the binary.
// This allows the distroless runtime container to run migrations without
// needing the SQL files present on disk — the binary is entirely self-contained.
package migrations

import "embed"

// FS contains all *.sql migration files in this directory, embedded at compile time.
//
//go:embed *.sql
var FS embed.FS
