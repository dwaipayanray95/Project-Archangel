package docker

import (
	"bufio"
	"context"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
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

	// Docker only multiplexes /logs output into the 8-byte-header framed
	// protocol for containers created without a TTY - a TTY container's
	// logs are raw bytes, and parsing them as framed would misinterpret
	// arbitrary log content as stream-type/payload-size headers.
	tty, err := defaultClient.IsTTY(ctx, id)
	if err != nil {
		tty = false
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

	reader := bufio.NewReader(stream)

	emit := func(streamType byte, raw string) bool {
		clean := strings.TrimRight(raw, "\r\n")
		if clean == "" {
			return true
		}

		level := "INFO"
		if streamType == 2 {
			level = "ERROR"
		} else if strings.Contains(strings.ToUpper(clean), "WARN") {
			level = "WARN"
		} else if strings.Contains(strings.ToUpper(clean), "ERR") {
			level = "ERROR"
		}

		ts := time.Now().Format("15:04:05")
		// Docker with timestamps=1 outputs: 2026-09-11T09:12:34.123456789Z <message>
		if len(clean) > 31 && clean[4] == '-' && clean[7] == '-' && (clean[10] == 'T' || clean[10] == ' ') {
			if t, err := time.Parse(time.RFC3339Nano, strings.Replace(clean[:30], " ", "T", 1)); err == nil {
				ts = t.Format("15:04:05")
				clean = strings.TrimSpace(clean[30:])
			}
		}

		entry := LogEntry{
			TS:     ts,
			Level:  level,
			Source: id,
			Text:   clean,
		}
		return conn.WriteJSON(entry) == nil
	}

	if tty {
		// Raw, unframed byte stream - read line by line.
		for {
			line, err := reader.ReadString('\n')
			if line != "" && !emit(1, line) {
				break
			}
			if err != nil {
				break
			}
		}
		return
	}

	// Docker Multiplex Log Protocol:
	// Each frame starts with an 8-byte header:
	//   header[0] = stream type (1 = stdout, 2 = stderr, 0 = stdin)
	//   header[1..3] = 0 (reserved)
	//   header[4..7] = uint32 big-endian payload size
	headerBuf := make([]byte, 8)

	for {
		// Read 8-byte header
		_, err := io.ReadFull(reader, headerBuf)
		if err != nil {
			break
		}

		streamType := headerBuf[0]
		payloadSize := binary.BigEndian.Uint32(headerBuf[4:8])

		// Bound frame size to 1MB to prevent memory exhaustion
		if payloadSize > 1024*1024 {
			break
		}

		payload := make([]byte, payloadSize)
		_, err = io.ReadFull(reader, payload)
		if err != nil {
			break
		}

		if !emit(streamType, string(payload)) {
			break
		}
	}
}
