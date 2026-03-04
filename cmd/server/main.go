package main

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gregoryforel/recipe-platform/internal/domain"
	"github.com/gregoryforel/recipe-platform/internal/handler"
	"github.com/gregoryforel/recipe-platform/internal/middleware"
	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	logger := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		dbURL = "postgres://recipe:recipe@localhost:5432/recipe_platform?sslmode=disable"
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	pool, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		logger.Error("failed to create connection pool", "error", err)
		os.Exit(1)
	}
	defer pool.Close()

	// For compile-recipes, wait for DB synchronously before proceeding
	if len(os.Args) > 1 && os.Args[1] == "compile-recipes" {
		if err := waitForDB(ctx, pool, logger); err != nil {
			logger.Error("database not ready", "error", err)
			os.Exit(1)
		}
		logger.Info("compiling all recipes...")
		if err := domain.CompileAllRecipes(ctx, pool, false); err != nil {
			logger.Error("failed to compile recipes", "error", err)
			os.Exit(1)
		}
		logger.Info("all recipes compiled successfully")
		return
	}

	// For server mode, retry DB connection in background
	go waitForDB(ctx, pool, logger)

	h := handler.New(pool, logger)
	mux := http.NewServeMux()
	h.RegisterRoutes(mux)

	wrapped := middleware.Chain(
		mux,
		middleware.Recovery(logger),
		middleware.Logger(logger),
		middleware.UnitSystem,
		middleware.AuthStub,
	)

	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      wrapped,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Graceful shutdown
	go func() {
		sigCh := make(chan os.Signal, 1)
		signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
		<-sigCh
		logger.Info("shutting down server...")
		shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer shutdownCancel()
		srv.Shutdown(shutdownCtx)
	}()

	logger.Info(fmt.Sprintf("server starting on :%s", port))
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		logger.Error("server error", "error", err)
		os.Exit(1)
	}
}

// waitForDB retries the database ping until it succeeds or the context is cancelled.
func waitForDB(ctx context.Context, pool *pgxpool.Pool, logger *slog.Logger) error {
	for i := 0; i < 30; i++ {
		if err := pool.Ping(ctx); err == nil {
			logger.Info("connected to database")
			return nil
		}
		logger.Info("waiting for database...", "attempt", i+1)
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(2 * time.Second):
		}
	}
	return fmt.Errorf("database not ready after 60 seconds")
}
