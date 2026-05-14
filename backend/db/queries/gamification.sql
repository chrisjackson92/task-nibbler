-- name: CreateGamificationState :one
INSERT INTO gamification_state (user_id, streak_count, has_completed_first_task, tree_health_score)
VALUES ($1, 0, false, 50)
RETURNING *;

-- name: GetGamificationState :one
SELECT * FROM gamification_state WHERE user_id = $1 LIMIT 1;
