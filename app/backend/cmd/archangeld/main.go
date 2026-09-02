// Command archangeld is Project Archangel's control-plane server: a single
// binary exposing the server's terminal, files, services, resource stats,
// Docker, and OCI instance controls to the Flutter app, reachable only over
// a WireGuard tunnel.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/dwaipayanray95/project-archangel/backend/internal/api"
	"github.com/dwaipayanray95/project-archangel/backend/internal/auth"
	"github.com/dwaipayanray95/project-archangel/backend/internal/config"
	"github.com/dwaipayanray95/project-archangel/backend/internal/terminal"
)

func main() {
	if len(os.Args) > 1 && os.Args[1] == "gen-token" {
		runGenToken()
		return
	}

	fs := flag.NewFlagSet("archangeld", flag.ExitOnError)
	configPath := fs.String("config", "/etc/archangel/config.yaml", "path to config.yaml")
	// Ignore the error: ExitOnError already handles a bad flag by printing
	// usage and exiting, so there's nothing left to check here.
	_ = fs.Parse(os.Args[1:])

	cfg, err := config.Load(*configPath)
	if err != nil {
		slog.Error("failed to load config", "err", err)
		os.Exit(1)
	}

	router := api.NewRouter(cfg.TokenHash)

	srv := &http.Server{
		Addr:    cfg.Addr(),
		Handler: router,
		// Guards the handshake phase only (Slowloris-class protection) -
		// once a connection is upgraded to a WebSocket it's hijacked out of
		// net/http's management, so this can't cut off a live terminal
		// session.
		ReadHeaderTimeout: 10 * time.Second,
	}

	// Run the server in the background so the main goroutine can wait for a
	// shutdown signal instead.
	serveErr := make(chan error, 1)
	go func() {
		slog.Info("archangeld starting", "addr", cfg.Addr())
		serveErr <- srv.ListenAndServe()
	}()

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	select {
	case err := <-serveErr:
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			slog.Error("server exited", "err", err)
			os.Exit(1)
		}
	case <-ctx.Done():
		slog.Info("shutting down")

		// WebSocket connections are hijacked out of net/http's request
		// tracking once upgraded, so srv.Shutdown alone would never close
		// or even notice them - close them explicitly first so their PTY
		// child processes get killed and reaped instead of orphaned.
		terminal.CloseAll()

		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := srv.Shutdown(shutdownCtx); err != nil {
			slog.Error("graceful shutdown failed", "err", err)
		}
	}
}

// runGenToken generates a fresh auth token, prints it once (the only time
// it's ever shown in plaintext), and prints the config line to paste into
// config.yaml. It deliberately does not write the config file itself -
// the operator should see and confirm the hash going into place.
func runGenToken() {
	token, hash, err := auth.GenerateToken()
	if err != nil {
		fmt.Fprintln(os.Stderr, "failed to generate token:", err)
		os.Exit(1)
	}

	fmt.Println("New Archangel API token (shown once, save it now):")
	fmt.Println()
	fmt.Println("  " + token)
	fmt.Println()
	fmt.Println("Add this line to /etc/archangel/config.yaml:")
	fmt.Println()
	fmt.Printf("  token_hash: %q\n", hash)
	fmt.Println()
	fmt.Println("Pair this token into the Flutter app - it is never stored in plaintext on the server.")
}
