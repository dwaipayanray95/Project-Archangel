// Package api wires up the HTTP route table. Each feature package
// (terminal, files, services, ...) owns its own handlers; this file just
// mounts them and applies the auth middleware.
package api

import (
	"encoding/json"
	"net/http"

	"github.com/dwaipayanray95/project-archangel/backend/internal/auth"
	"github.com/dwaipayanray95/project-archangel/backend/internal/terminal"
)

// NewRouter builds the full route table. tokenHash is the expected auth
// token's SHA-256 hash - every route except /api/v1/health requires it.
func NewRouter(tokenHash string) http.Handler {
	mux := http.NewServeMux()

	// No auth: lets the app tell "connected but backend down" apart from
	// "can't reach the server at all".
	mux.HandleFunc("GET /api/v1/health", healthHandler)

	mux.Handle("GET /ws/terminal", auth.Middleware(tokenHash, http.HandlerFunc(terminal.Handler)))

	// Milestones 2-4 add their routes here: /api/v1/files/*,
	// /api/v1/services/*, /ws/stats, /api/v1/docker/*, /api/v1/oci/*.

	return withLogging(mux)
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}
