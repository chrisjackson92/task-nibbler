-- name: GetGamificationState :one
SELECT * FROM gamification_state
WHERE user_id = $1
LIMIT 1;

-- name: CreateGamificationState :one
INSERT INTO gamification_state (user_id, tree_health_score)
VALUES ($1, 50)
RETURNING *;

-- name: UpdateGamificationOnComplete :one
UPDATE gamification_state SET
  streak_count             = $1,
  last_active_date         = $2,
  has_completed_first_task = TRUE,
  tree_health_score        = LEAST(tree_health_score + 5, 100),
  updated_at               = NOW()
WHERE user_id = $3
RETURNING *;
