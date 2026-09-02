// Command archangeld is Project Archangel's control-plane server: a single
// binary exposing the server's terminal, files, services, resource stats,
// Docker, and OCI instance controls to the Flutter app, reachable only over
// a WireGuard tunnel.
package main

import (
	"fmt"
	"log/slog"
	"net/http"
	"os"

	"github.com/dwaipayanray95/project-archangel/backend/internal/api"
	"github.com/dwaipayanray95/project-archangel/backend/internal/auth"
	"github.com/dwaipayanray95/project-archangel/backend/internal/config"
)

func main() {
	if len(os.Args) > 1 && os.Args[1] == "gen-token" {
		runGenToken()
		return
	}

	configPath := "/etc/archangel/config.yaml"
	if len(os.Args) > 1 && os.Args[1] == "-config" && len(os.Args) > 2 {
		configPath = os.Args[2]
	}

	cfg, err := config.Load(configPath)
	if err != nil {
		slog.Error("failed to load config", "err", err)
		os.Exit(1)
	}

	router := api.NewRouter(cfg.TokenHash)

	slog.Info("archangeld starting", "addr", cfg.Addr())
	if err := http.ListenAndServe(cfg.Addr(), router); err != nil {
		slog.Error("server exited", "err", err)
		os.Exit(1)
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
