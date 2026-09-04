package system

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{}

// MetricsHandler handles GET /api/v1/system/metrics
func MetricsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	metrics := GetCollector().Latest()
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(metrics); err != nil {
		slog.Error("failed encoding metrics response", "err", err)
	}
}

// ProcessesHandler handles GET /api/v1/system/processes
func ProcessesHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	procs, err := ListProcesses()
	if err != nil {
		slog.Error("failed listing processes", "err", err)
		http.Error(w, "failed listing processes", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(procs)
}

type killRequest struct {
	Force bool `json:"force"`
}

// ProcessKillHandler handles POST /api/v1/system/processes/{pid}/kill
func ProcessKillHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	pidStr := r.PathValue("pid")
	pid, err := strconv.Atoi(pidStr)
	if err != nil {
		http.Error(w, "invalid pid", http.StatusBadRequest)
		return
	}

	var req killRequest
	if r.Body != nil {
		_ = json.NewDecoder(r.Body).Decode(&req)
	}

	if err := KillProcess(pid, req.Force); err != nil {
		slog.Warn("kill process failed", "pid", pid, "err", err)
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"status": "ok", "pid": pid})
}

type reniceRequest struct {
	Priority int `json:"priority"`
}

// ProcessReniceHandler handles POST /api/v1/system/processes/{pid}/renice
func ProcessReniceHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	pidStr := r.PathValue("pid")
	pid, err := strconv.Atoi(pidStr)
	if err != nil {
		http.Error(w, "invalid pid", http.StatusBadRequest)
		return
	}

	var req reniceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}

	if err := ReniceProcess(pid, req.Priority); err != nil {
		slog.Warn("renice process failed", "pid", pid, "err", err)
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"status": "ok", "pid": pid, "priority": req.Priority})
}

// StatsWsHandler handles GET /ws/stats for live streaming metrics
func StatsWsHandler(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		slog.Error("failed upgrading ws/stats", "err", err)
		return
	}
	defer conn.Close()

	// Push metrics immediately upon connect
	collector := GetCollector()
	if err := conn.WriteJSON(collector.Latest()); err != nil {
		return
	}

	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()

	// Read loop to detect client disconnect
	done := make(chan struct{})
	go func() {
		defer close(done)
		for {
			if _, _, err := conn.ReadMessage(); err != nil {
				return
			}
		}
	}()

	for {
		select {
		case <-done:
			return
		case <-ticker.C:
			metrics := collector.Latest()
			conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
			if err := conn.WriteJSON(metrics); err != nil {
				slog.Debug("stats ws client disconnected", "err", err)
				return
			}
		}
	}
}
