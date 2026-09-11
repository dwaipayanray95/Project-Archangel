// Package api wires up the HTTP route table. Each feature package
// (terminal, files, services, ...) owns its own handlers; this file just
// mounts them and applies the auth middleware.
package api

import (
	"encoding/json"
	"net/http"

	"github.com/dwaipayanray95/project-archangel/backend/internal/auth"
	"github.com/dwaipayanray95/project-archangel/backend/internal/devops"
	"github.com/dwaipayanray95/project-archangel/backend/internal/docker"
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

	// Docker / Containers Cockpit
	mux.Handle("GET /api/v1/docker/containers", auth.Middleware(verify, http.HandlerFunc(docker.ContainersHandler)))
	mux.Handle("POST /api/v1/docker/containers/{id}/{action}", auth.Middleware(verify, http.HandlerFunc(docker.ContainerActionHandler)))
	mux.Handle("GET /ws/docker/containers/{id}/logs", auth.Middleware(verify, http.HandlerFunc(docker.ContainerLogsWsHandler)))

	// DevOps (Services, Scheduled Timers, Reverse Proxy, Deployments)
	mux.Handle("GET /api/v1/devops/services", auth.Middleware(verify, http.HandlerFunc(devops.ServicesHandler)))
	mux.Handle("POST /api/v1/devops/services/{name}/{action}", auth.Middleware(verify, http.HandlerFunc(devops.ServiceActionHandler)))
	mux.Handle("GET /api/v1/devops/scheduled", auth.Middleware(verify, http.HandlerFunc(devops.ScheduledHandler)))
	mux.Handle("POST /api/v1/devops/scheduled/{name}/run", auth.Middleware(verify, http.HandlerFunc(devops.ScheduledRunHandler)))
	mux.Handle("GET /api/v1/devops/proxy", auth.Middleware(verify, http.HandlerFunc(devops.ProxyHandler)))
	mux.Handle("POST /api/v1/devops/proxy/{domain}/test", auth.Middleware(verify, http.HandlerFunc(devops.ProxyTestHandler)))
	mux.Handle("GET /api/v1/devops/deployments", auth.Middleware(verify, http.HandlerFunc(devops.DeploymentsHandler)))
	mux.Handle("POST /api/v1/devops/deployments/{name}/run", auth.Middleware(verify, http.HandlerFunc(devops.DeploymentRunHandler)))

	return withLogging(mux)
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{
		"status":  "ok",
		"version": version.Version,
	})
}
