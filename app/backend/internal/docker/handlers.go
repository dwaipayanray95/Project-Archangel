package docker

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/gorilla/websocket"
)

var defaultClient = NewClient()

// ContainersHandler handles GET /api/v1/docker/containers
func ContainersHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	w.Header().Set("Content-Type", "application/json")

	if !defaultClient.IsAvailable() {
		_ = json.NewEncoder(w).Encode(FallbackOverview())
		return
	}

	containers, err := defaultClient.ListContainers()
	if err != nil {
		_ = json.NewEncoder(w).Encode(FallbackOverview())
		return
	}

	running := 0
	stopped := 0
	stacksMap := make(map[string]int)
	for _, c := range containers {
		if c.Running {
			running++
		} else {
			stopped++
		}
		stacksMap[c.Stack]++
	}

	stacks := make([]string, 0, len(stacksMap))
	stackMeta := make(map[string]string)
	for s, count := range stacksMap {
		stacks = append(stacks, s)
		stackMeta[s] = fmt.Sprintf("compose stack · %d services", count)
	}

	overview := ContainersOverview{
		DockerAvailable: true,
		EngineVersion:   defaultClient.GetVersion(),
		RunningCount:    running,
		StoppedCount:    stopped,
		TotalImagesSize: "—",
		Containers:      containers,
		Stacks:          stacks,
		StackMeta:       stackMeta,
	}

	_ = json.NewEncoder(w).Encode(overview)
}

// ContainerActionHandler handles POST /api/v1/docker/containers/{id}/{action}
func ContainerActionHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	id := r.PathValue("id")
	action := r.PathValue("action")
	if id == "" || action == "" {
		http.Error(w, "missing container id or action", http.StatusBadRequest)
		return
	}

	w.Header().Set("Content-Type", "application/json")

	if !defaultClient.IsAvailable() {
		// Simulate action success on mock containers
		_ = json.NewEncoder(w).Encode(ActionResponse{
			Success: true,
			Message: fmt.Sprintf("%s action simulated for %s (demo mode)", action, id),
		})
		return
	}

	err := defaultClient.ContainerAction(id, action)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(ActionResponse{
			Success: false,
			Message: fmt.Sprintf("failed to %s container: %v", action, err),
		})
		return
	}

	_ = json.NewEncoder(w).Encode(ActionResponse{
		Success: true,
		Message: fmt.Sprintf("container %s %sed successfully", id, action),
	})
}

// CheckOrigin left at its default (same-origin check) - matches the
// hardened pattern in internal/system's stats upgrader; this endpoint is
// already gated by auth.Middleware regardless.
var upgrader = websocket.Upgrader{}

// ContainerLogsWsHandler handles GET /ws/docker/containers/{id}/logs
func ContainerLogsWsHandler(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if id == "" {
		http.Error(w, "missing container id", http.StatusBadRequest)
		return
	}

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	defer conn.Close()

	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()

	if !defaultClient.IsAvailable() {
		// Stream mock demo logs
		demoLogs := []LogEntry{
			{TS: "06:14:02", Level: "INFO", Source: "http.log.access", Text: "handled request GET /api/v1/status status=200"},
			{TS: "06:14:05", Level: "INFO", Source: "http.log.access", Text: "handled request POST /api/v1/auth status=200"},
			{TS: "06:14:11", Level: "WARN", Source: "http.log.access", Text: "blocked probe GET /.env status=403"},
			{TS: "06:14:19", Level: "INFO", Source: "worker", Text: "background job finished successfully"},
		}

		for _, l := range demoLogs {
			if err := conn.WriteJSON(l); err != nil {
				return
			}
		}

		ticker := time.NewTicker(4 * time.Second)
		defer ticker.Stop()

		for {
			select {
			case <-ctx.Done():
				return
			case t := <-ticker.C:
				l := LogEntry{
					TS:     t.Format("15:04:05"),
					Level:  "INFO",
					Source: "docker",
					Text:   "heartbeat check ok · container healthy",
				}
				if err := conn.WriteJSON(l); err != nil {
					return
				}
			}
		}
	}

	stream, err := defaultClient.StreamLogsReader(ctx, id, 100)
	if err != nil {
		_ = conn.WriteJSON(LogEntry{
			TS:     time.Now().Format("15:04:05"),
			Level:  "ERROR",
			Source: "docker",
			Text:   fmt.Sprintf("failed to attach to logs: %v", err),
		})
		return
	}
	defer stream.Close()

	scanner := bufio.NewScanner(stream)
	for scanner.Scan() {
		raw := scanner.Text()
		// Docker stream multiplex header is 8 bytes if present
		clean := raw
		if len(raw) > 8 {
			clean = raw[8:]
		}

		ts := time.Now().Format("15:04:05")
		level := "INFO"
		if strings.Contains(strings.ToUpper(clean), "WARN") {
			level = "WARN"
		} else if strings.Contains(strings.ToUpper(clean), "ERR") {
			level = "ERROR"
		}

		entry := LogEntry{
			TS:     ts,
			Level:  level,
			Source: id,
			Text:   clean,
		}

		if err := conn.WriteJSON(entry); err != nil {
			break
		}
	}
}
