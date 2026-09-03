package system

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"time"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true // WireGuard tunnel origin check
	},
}

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
