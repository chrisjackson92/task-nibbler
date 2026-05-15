package repositories

import "errors"

// Sentinel errors returned by all repositories.
// Callers (services) translate these into HTTP error codes via apierr.
var (
	// ErrNotFound is returned when a query matches zero rows.
	ErrNotFound = errors.New("not found")

	// ErrConflict is returned when an operation cannot proceed due to current
	// resource state — e.g. completing an already-completed task.
	ErrConflict = errors.New("conflict")

	// ErrDuplicate is returned on unique constraint violations.
	ErrDuplicate = errors.New("duplicate")
)
