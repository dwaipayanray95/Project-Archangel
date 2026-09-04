// Package api wires up the HTTP route table. Each feature package
// (terminal, files, services, ...) owns its own handlers; this file just
// mounts them and applies the auth middleware.
package api

import (
	"encoding/json"
	"net/http"

	"github.com/dwaipayanray95/project-archangel/backend/internal/auth"
	"github.com/dwaipayanray95/project-archangel/backend/internal/files"
	"github.com/dwaipayanray95/project-archangel/backend/internal/system"
	"github.com/dwaipayanray95/project-archangel/backend/internal/terminal"
	"github.com/dwaipayanray95/project-archangel/backend/internal/version"
)

// NewRouter builds the full route table. verify decides whether a
// request's token hash is valid - every route except /api/v1/health
// requires it.
func NewRouter(verify auth.Verifier) http.Handler {
	mux := http.NewServeMux()

	// No auth: lets the app tell "connected but backend down" apart from
	// "can't reach the server at all".
	mux.HandleFunc("GET /api/v1/health", healthHandler)

	mux.Handle("GET /ws/terminal", auth.Middleware(verify, http.HandlerFunc(terminal.Handler)))

	// System metrics, processes, and live stats stream
	mux.Handle("GET /api/v1/system/metrics", auth.Middleware(verify, http.HandlerFunc(system.MetricsHandler)))
	mux.Handle("GET /api/v1/system/processes", auth.Middleware(verify, http.HandlerFunc(system.ProcessesHandler)))
	mux.Handle("POST /api/v1/system/processes/{pid}/kill", auth.Middleware(verify, http.HandlerFunc(system.ProcessKillHandler)))
	mux.Handle("POST /api/v1/system/processes/{pid}/renice", auth.Middleware(verify, http.HandlerFunc(system.ProcessReniceHandler)))
	mux.Handle("GET /ws/stats", auth.Middleware(verify, http.HandlerFunc(system.StatsWsHandler)))

	// Files explorer & previewer
	mux.Handle("GET /api/v1/files/list", auth.Middleware(verify, http.HandlerFunc(files.ListHandler)))
	mux.Handle("GET /api/v1/files/read", auth.Middleware(verify, http.HandlerFunc(files.ReadHandler)))
	mux.Handle("GET /api/v1/files/download", auth.Middleware(verify, http.HandlerFunc(files.DownloadHandler)))

	// Milestones 3-4 add their routes here:
	// /api/v1/services/*, /api/v1/docker/*, /api/v1/oci/*.

	return withLogging(mux)
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{
		"status":  "ok",
		"version": version.Version,
	})
}
