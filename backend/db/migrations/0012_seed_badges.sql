-- +goose Up
-- +goose StatementBegin

-- Seed all 14 badges per BLU-002-SD §2.
-- This table is read-only at runtime; all badges are inserted here at deploy time.
-- Badge IDs are system identifiers used by the award engine — never change existing IDs.

INSERT INTO badges (id, name, description, emoji, trigger_type) VALUES

-- ── Streak Milestones ─────────────────────────────────────────────────────────
('FIRST_NIBBLE',
 'First Nibble',
 'You completed your very first task. Every journey starts with a single nibble!',
 '🌱',
 'FIRST_TASK'),

('STREAK_7',
 'Week Warrior',
 'You maintained a 7-day streak. Your tree is starting to grow!',
 '🔥',
 'STREAK_MILESTONE'),

('STREAK_14',
 'Fortnight Fighter',
 'Two weeks of consistency — your companion is cheering you on!',
 '⚡',
 'STREAK_MILESTONE'),

('STREAK_30',
 'Monthly Maven',
 'A full month of showing up. You are unstoppable.',
 '🏆',
 'STREAK_MILESTONE'),

('STREAK_100',
 'Century Club',
 '100 days of consistency. Your tree is magnificent.',
 '💯',
 'STREAK_MILESTONE'),

('STREAK_365',
 'Unstoppable',
 'One full year of daily tasking. Legendary.',
 '🌟',
 'STREAK_MILESTONE'),

-- ── Task Volume × Streak ──────────────────────────────────────────────────────
('CONSISTENT_WEEK',
 'Consistent Week',
 'You completed 3 or more tasks every day for a full week. True consistency!',
 '🎯',
 'VOLUME_STREAK'),

('CONSISTENT_MONTH',
 'Consistent Month',
 'You completed 3 or more tasks every day for a full month. Extraordinary!',
 '🚀',
 'VOLUME_STREAK'),

('PRODUCTIVE_WEEK',
 'Productive Week',
 'You completed 5 or more tasks every day for a full week. Powerhouse!',
 '🎯',
 'VOLUME_STREAK'),

('PRODUCTIVE_MONTH',
 'Productive Month',
 'You completed 5 or more tasks every day for a full month. Elite performer!',
 '🚀',
 'VOLUME_STREAK'),

('OVERACHIEVER',
 'Daily Overachiever',
 'You completed 10 or more tasks in a single day. Incredible!',
 '⚡',
 'DAILY_VOLUME'),

-- ── Tree Health ───────────────────────────────────────────────────────────────
('TREE_HEALTHY',
 'Sprout',
 'Your tree reached a healthy state for the first time. Keep it growing!',
 '🌿',
 'TREE_HEALTH'),

('TREE_THRIVING',
 'In Bloom',
 'Your tree is thriving! Consistent effort has made it flourish.',
 '🌸',
 'TREE_HEALTH'),

('TREE_SUSTAINED',
 'Full Canopy',
 'Your tree has been thriving for 7 consecutive days. Magnificent!',
 '🌳',
 'TREE_HEALTH');

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DELETE FROM badges WHERE id IN (
  'FIRST_NIBBLE', 'STREAK_7', 'STREAK_14', 'STREAK_30', 'STREAK_100', 'STREAK_365',
  'CONSISTENT_WEEK', 'CONSISTENT_MONTH', 'PRODUCTIVE_WEEK', 'PRODUCTIVE_MONTH',
  'OVERACHIEVER', 'TREE_HEALTHY', 'TREE_THRIVING', 'TREE_SUSTAINED'
);
-- +goose StatementEnd
