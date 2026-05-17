-- Add companion type selection to gamification_state (SPR-009-MB)
ALTER TABLE gamification_state
    ADD COLUMN IF NOT EXISTS sprite_type TEXT NOT NULL DEFAULT 'sprite_a',
    ADD COLUMN IF NOT EXISTS tree_type   TEXT NOT NULL DEFAULT 'tree_a';
