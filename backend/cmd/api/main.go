// Task Nibbles API — v1.0.0 production release
// Package main is the entry point for the Task Nibbles API server.
// It wires dependencies, starts the Gin HTTP server, and runs database migrations
// when invoked with the "migrate" subcommand.
//
// @title        Task Nibbles API
// @version      1.0.0
// @description  Go + Gin backend for the Task Nibbles task management app.
// @contact.name Task Nibbles Team
// @BasePath     /api/v1
// @securityDefinitions.apikey BearerAuth
// @in header
// @name Authorization
package main

import (
	"context"
	"database/sql"
	"log"
	"log/slog"
	"os"
	"time"

	"github.com/chrisjackson92/task-nibbler/backend/internal/config"
	"github.com/chrisjackson92/task-nibbler/backend/internal/handlers"
	"github.com/chrisjackson92/task-nibbler/backend/internal/jobs"
	"github.com/chrisjackson92/task-nibbler/backend/internal/middleware"
	"github.com/chrisjackson92/task-nibbler/backend/internal/repositories"
	s3client "github.com/chrisjackson92/task-nibbler/backend/internal/s3client"
	"github.com/chrisjackson92/task-nibbler/backend/internal/services"
	"github.com/gin-gonic/gin"
	"github.com/go-co-op/gocron/v2"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"

	migrations "github.com/chrisjackson92/task-nibbler/backend/db/migrations"

	// Swagger UI
	swaggerFiles "github.com/swaggo/files"
	ginSwagger "github.com/swaggo/gin-swagger"

	// Auto-import generated docs (created by swaggo/swag)
	_ "github.com/chrisjackson92/task-nibbler/backend/docs"
)

const version = "1.0.0"

func main() {
	// Handle migration subcommand FIRST — before config.Load().
	// The migrate path only needs DATABASE_URL; loading the full config here
	// would fatal on missing secrets (RESEND_API_KEY etc.) during fly deploy
	// release_command, when only the DB connection is needed.
	if len(os.Args) > 1 && os.Args[1] == "migrate" {
		databaseURL := os.Getenv("DATABASE_URL")
		if databaseURL == "" {
			log.Fatal("FATAL: DATABASE_URL is required for migrate")
		}
		slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo})))
		if err := runMigrations(databaseURL); err != nil {
			log.Fatalf("migration failed: %v", err)
		}
		slog.Info("migrations completed successfully")
		return
	}

	// Full config load for normal server startup
	cfg := config.Load()
	level := slog.LevelInfo
	if cfg.LogLevel == "debug" {
		level = slog.LevelDebug
	}
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: level})))

	// Setup database pool
	pool := setupDatabase(cfg.DatabaseURL)
	defer pool.Close()

	// Wire repositories
	userRepo := repositories.NewUserRepository(pool)
	refreshRepo := repositories.NewRefreshTokenRepository(pool)
	passwordRepo := repositories.NewPasswordResetRepository(pool)
	gamifRepo := repositories.NewGamificationRepository(pool)
	taskRepo := repositories.NewTaskRepository(pool)
	attachmentRepo := repositories.NewAttachmentRepository(pool)
	badgeRepo := repositories.NewBadgeRepository(pool)
	ruleRepo := repositories.NewRecurringRuleRepository(pool)

	// Wire S3 client (B-015)
	s3, err := s3client.New(context.Background(), s3client.Config{
		AccessKeyID:     cfg.AWSAccessKeyID,
		SecretAccessKey: cfg.AWSSecretAccessKey,
		Region:          cfg.AWSRegion,
		Bucket:          cfg.AWSS3Bucket,
	})
	if err != nil {
		log.Fatalf("FATAL: cannot create S3 client: %v", err)
	}

	// Wire services
	emailSvc := services.NewEmailService(cfg.ResendAPIKey, cfg.ResendFromEmail, cfg.AppBaseURL)
	authSvc := services.NewAuthService(userRepo, refreshRepo, passwordRepo, gamifRepo, emailSvc, cfg.JWTSecret, cfg.JWTRefreshSecret)
	gamifSvc := services.NewGamificationService(gamifRepo, badgeRepo)
	taskSvc := services.NewTaskService(taskRepo, gamifSvc)
	attachmentSvc := services.NewAttachmentService(attachmentRepo, s3)
	recurringSvc := services.NewRecurringService(taskRepo, ruleRepo)

	// Wire handlers
	authHandler := handlers.NewAuthHandler(authSvc)
	healthHandler := handlers.NewHealthHandler(pool, version)
	taskHandler := handlers.NewTaskHandler(taskSvc, recurringSvc)
	attachmentHandler := handlers.NewAttachmentHandler(attachmentSvc)
	gamificationHandler := handlers.NewGamificationHandler(gamifSvc)
	userHandler := handlers.NewUserHandler(userRepo)

	// Setup router
	if cfg.IsProduction() {
		gin.SetMode(gin.ReleaseMode)
	}

	r := gin.New()

	// Global middleware (order matters — see BLU-003 §4)
	r.Use(middleware.Recovery())
	r.Use(middleware.Logger())
	r.Use(middleware.CORS())

	// Swagger UI
	r.GET("/swagger/*any", ginSwagger.WrapHandler(swaggerFiles.Handler))

	// Health check (no auth, no rate limit)
	r.GET("/health", healthHandler.Health)

	// Connectivity ping — no auth, no DB. Used by mobile debug builds to
	// verify the app can reach the API independently of DNS/proxy issues.
	r.GET("/api/v1/ping", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"ok":         true,
			"server":     "task-nibbles-api",
			"env":        "production",
			"client_ip":  c.ClientIP(),
			"user_agent": c.Request.UserAgent(),
		})
	})

	// Public auth routes (rate limited)
	auth := r.Group("/api/v1/auth")
	auth.Use(middleware.RateLimit(5, time.Minute))
	{
		auth.POST("/register", authHandler.Register)
		auth.POST("/login", authHandler.Login)
		auth.POST("/refresh", authHandler.Refresh)
		auth.POST("/forgot-password", authHandler.ForgotPassword)
		auth.POST("/reset-password", authHandler.ResetPassword)
	}

	// Protected routes (JWT required)
	api := r.Group("/api/v1")
	api.Use(middleware.Auth(cfg.JWTSecret))
	{
		api.DELETE("/auth/logout", authHandler.Logout)
		api.DELETE("/auth/account", authHandler.DeleteAccount)

		// Task routes (B-011, B-012, B-039, B-040, B-041)
		tasks := api.Group("/tasks")
		taskHandler.RegisterRoutes(tasks)

		// Attachment routes (B-015, B-042–B-045)
		attachments := tasks.Group("/:id/attachments")
		attachmentHandler.RegisterRoutes(attachments)

		// Gamification routes (B-038, B-054) — SPR-004-BE
		gamif := api.Group("/gamification")
		gamificationHandler.RegisterRoutes(gamif)

		// User profile routes (SPR-008-MB)
		api.PATCH("/users/me", userHandler.UpdateMe)

	}

	// Nightly cron scheduler (B-014, B-045, B-026)
	attachmentCleanup := jobs.NewAttachmentCleanupJob(attachmentRepo, s3)
	recurringExpansion := jobs.NewRecurringExpansionJob(ruleRepo, taskRepo, userRepo)
	s, err := gocron.NewScheduler()
	if err != nil {
		log.Fatalf("FATAL: cannot create scheduler: %v", err)
	}
	// 00:05 UTC — clean up PENDING attachment rows older than 1 hour
	_, err = s.NewJob(
		gocron.CronJob("5 0 * * *", false),
		gocron.NewTask(func() {
			slog.Info("nightly cron: attachment cleanup tick")
			attachmentCleanup.Run(context.Background())
		}),
	)
	if err != nil {
		log.Fatalf("FATAL: cannot register attachment cleanup job: %v", err)
	}
	// 00:15 UTC — expand active recurring rules for next 30 days (idempotent)
	_, err = s.NewJob(
		gocron.CronJob("15 0 * * *", false),
		gocron.NewTask(func() {
			slog.Info("nightly cron: recurring expansion tick")
			recurringExpansion.Run(context.Background())
		}),
	)
	if err != nil {
		log.Fatalf("FATAL: cannot register recurring expansion job: %v", err)
	}
	// 00:30 UTC — gamification nightly decay + overdue penalties (B-063)
	gamNightlyJob := jobs.NewGamificationNightlyJob(gamifSvc, userRepo, taskRepo)
	_, err = s.NewJob(
		gocron.CronJob("30 0 * * *", false),
		gocron.NewTask(func() {
			slog.Info("nightly cron: gamification decay + overdue penalty tick")
			gamNightlyJob.Run()
		}),
	)
	if err != nil {
		log.Fatalf("FATAL: cannot register gamification nightly job: %v", err)
	}
	s.Start()
	defer s.Shutdown()

	slog.Info("starting Task Nibbles API",
		"port", cfg.Port,
		"env", cfg.AppEnv,
		"version", version,
	)

	if err := r.Run(":" + cfg.Port); err != nil {
		log.Fatalf("server failed: %v", err)
	}
}

// setupDatabase creates and validates a pgx connection pool.
// Panics if the database is unreachable at startup.
func setupDatabase(databaseURL string) *pgxpool.Pool {
	poolCfg, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		log.Fatalf("FATAL: invalid DATABASE_URL: %v", err)
	}

	poolCfg.MaxConns = 25
	poolCfg.MinConns = 2
	poolCfg.MaxConnLifetime = 1 * time.Hour
	poolCfg.MaxConnIdleTime = 30 * time.Minute

	pool, err := pgxpool.NewWithConfig(context.Background(), poolCfg)
	if err != nil {
		log.Fatalf("FATAL: cannot create DB pool: %v", err)
	}

	// Verify connectivity
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := pool.Ping(ctx); err != nil {
		log.Fatalf("FATAL: database ping failed: %v", err)
	}

	slog.Info("database connected", "max_conns", 25)
	return pool
}

// runMigrations applies all pending goose migrations using the embedded SQL files.
// Migration files are compiled into the binary via db/migrations/migrations.go (embed.FS),
// so the distroless runtime container does not need them on disk.
func runMigrations(databaseURL string) error {
	// Use stdlib adapter so goose can use the pgx driver
	poolCfg, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		return err
	}

	pool, err := pgxpool.NewWithConfig(context.Background(), poolCfg)
	if err != nil {
		return err
	}
	defer pool.Close()

	db := stdlib.OpenDBFromPool(pool)
	defer func(db *sql.DB) { _ = db.Close() }(db)

	// Point goose at the embedded filesystem — no disk access needed
	goose.SetBaseFS(migrations.FS)

	if err := goose.SetDialect("postgres"); err != nil {
		return err
	}

	// "." = root of the embedded FS, which IS the db/migrations directory
	return goose.Up(db, ".")
}
// Production bootstrap: database_url sslmode=disable fix [TRB-008]
