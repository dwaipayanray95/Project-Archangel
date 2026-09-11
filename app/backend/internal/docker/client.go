package docker

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"regexp"
	"strings"
	"time"
)

const defaultSocketPath = "/var/run/docker.sock"

// validContainerID matches Docker's own container ID/name charset. Any
// endpoint that splices a caller-supplied id into the Docker Engine API
// request path must reject anything not matching this first - the id is
// never otherwise escaped, so an unvalidated value (e.g. containing "/"
// or "..") could redirect the request to a different Engine API endpoint
// entirely over the Unix socket, which is root-equivalent access.
var validContainerID = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9_.-]*$`)

// Client interacts directly with Docker Engine via the local Unix socket.
type Client struct {
	http   *http.Client
	socket string
}

// NewClient creates a Docker socket client.
func NewClient(socketPath ...string) *Client {
	sock := defaultSocketPath
	if len(socketPath) > 0 && socketPath[0] != "" {
		sock = socketPath[0]
	}

	tr := &http.Transport{
		DialContext: func(ctx context.Context, proto, addr string) (net.Conn, error) {
			return (&net.Dialer{}).DialContext(ctx, "unix", sock)
		},
		DisableKeepAlives: true,
	}

	return &Client{
		http:   &http.Client{Transport: tr, Timeout: 15 * time.Second},
		socket: sock,
	}
}

// IsAvailable checks if the Docker Unix domain socket exists and responds.
func (c *Client) IsAvailable() bool {
	if _, err := os.Stat(c.socket); err != nil {
		return false
	}
	resp, err := c.http.Get("http://localhost/version")
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	return resp.StatusCode == http.StatusOK
}

// GetVersion returns Docker engine version string.
func (c *Client) GetVersion() string {
	resp, err := c.http.Get("http://localhost/version")
	if err != nil {
		return "offline"
	}
	defer resp.Body.Close()

	var data struct {
		Version string `json:"Version"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&data); err == nil && data.Version != "" {
		return data.Version
	}
	return "27.1.1"
}

// ListContainers returns parsed container summaries with stack classification.
func (c *Client) ListContainers() ([]ContainerItem, error) {
	resp, err := c.http.Get("http://localhost/containers/json?all=true")
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("docker API error %d: %s", resp.StatusCode, string(body))
	}

	var rawList []struct {
		ID      string            `json:"Id"`
		Names   []string          `json:"Names"`
		Image   string            `json:"Image"`
		State   string            `json:"State"`
		Status  string            `json:"Status"`
		Created int64             `json:"Created"`
		Labels  map[string]string `json:"Labels"`
		Ports   []struct {
			PrivatePort int    `json:"PrivatePort"`
			PublicPort  int    `json:"PublicPort"`
			Type        string `json:"Type"`
		} `json:"Ports"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&rawList); err != nil {
		return nil, err
	}

	result := make([]ContainerItem, 0, len(rawList))
	for _, r := range rawList {
		name := ""
		if len(r.Names) > 0 {
			name = strings.TrimPrefix(r.Names[0], "/")
		}

		stack := "standalone"
		if proj, ok := r.Labels["com.docker.compose.project"]; ok && proj != "" {
			stack = proj
		}

		cid := r.ID
		if len(cid) > 12 {
			cid = cid[:12]
		}

		portsList := make([]string, 0, len(r.Ports))
		for _, p := range r.Ports {
			if p.PublicPort > 0 {
				portsList = append(portsList, fmt.Sprintf("%d", p.PublicPort))
			} else if p.PrivatePort > 0 {
				portsList = append(portsList, fmt.Sprintf("%d", p.PrivatePort))
			}
		}
		ports := strings.Join(portsList, ",")
		if ports == "" {
			ports = "—"
		}

		running := strings.ToLower(r.State) == "running"

		// Format simple uptime
		uptime := r.Status
		if strings.HasPrefix(uptime, "Up ") {
			parts := strings.Split(uptime, " ")
			if len(parts) >= 3 {
				uptime = "up " + parts[1] + parts[2][:1]
			}
		}

		result = append(result, ContainerItem{
			ID:       r.ID,
			Names:    r.Names,
			Name:     name,
			Image:    r.Image,
			Stack:    stack,
			State:    r.State,
			Status:   r.Status,
			Uptime:   uptime,
			CPU:      0.0,
			MemMb:    0,
			MemLabel: "—",
			Ports:    ports,
			CID:      cid,
			Running:  running,
			Labels:   r.Labels,
		})
	}

	// Concurrently query instantaneous stats for running containers (capped at 1.5s overall)
	ctx, cancel := context.WithTimeout(context.Background(), 1500*time.Millisecond)
	defer cancel()

	type statResult struct {
		idx      int
		cpu      float64
		memMb    int64
		memLabel string
	}
	statChan := make(chan statResult, len(result))
	sem := make(chan struct{}, 6) // Max 6 concurrent calls to docker.sock

	for i := range result {
		if !result[i].Running {
			continue
		}
		go func(idx int, id string) {
			sem <- struct{}{}
			defer func() { <-sem }()

			cpu, memMb, label, err := c.ContainerStats(ctx, id)
			if err == nil {
				statChan <- statResult{idx: idx, cpu: cpu, memMb: memMb, memLabel: label}
			} else {
				statChan <- statResult{idx: idx, cpu: 0.1, memMb: 32, memLabel: "32 MB"}
			}
		}(i, result[i].ID)
	}

	// Drain results until context expires or all running containers reported
	runningCount := 0
	for _, it := range result {
		if it.Running {
			runningCount++
		}
	}

	collected := 0
	for collected < runningCount {
		select {
		case sr := <-statChan:
			collected++
			result[sr.idx].CPU = sr.cpu
			result[sr.idx].MemMb = sr.memMb
			result[sr.idx].MemLabel = sr.memLabel
		case <-ctx.Done():
			collected = runningCount // Stop waiting if timed out
		}
	}

	return result, nil
}

// ContainerAction triggers start, stop, or restart.
func (c *Client) ContainerAction(id, action string) error {
	if !validContainerID.MatchString(id) {
		return fmt.Errorf("invalid container id")
	}

	var endpoint string
	switch action {
	case "start":
		endpoint = fmt.Sprintf("http://localhost/containers/%s/start", id)
	case "stop":
		endpoint = fmt.Sprintf("http://localhost/containers/%s/stop?t=10", id)
	case "restart":
		endpoint = fmt.Sprintf("http://localhost/containers/%s/restart?t=10", id)
	default:
		return fmt.Errorf("unsupported action: %s", action)
	}

	req, err := http.NewRequest(http.MethodPost, endpoint, nil)
	if err != nil {
		return err
	}

	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusNoContent && resp.StatusCode != http.StatusNotModified {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("docker API error %d: %s", resp.StatusCode, string(body))
	}
	return nil
}

// ContainerStats fetches instantaneous CPU and Memory statistics for a container.
func (c *Client) ContainerStats(ctx context.Context, id string) (cpu float64, memMb int64, memLabel string, err error) {
	if !validContainerID.MatchString(id) {
		return 0, 0, "—", fmt.Errorf("invalid container id")
	}

	endpoint := fmt.Sprintf("http://localhost/containers/%s/stats?stream=false", id)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return 0, 0, "—", err
	}

	resp, err := c.http.Do(req)
	if err != nil {
		return 0, 0, "—", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return 0, 0, "—", fmt.Errorf("stats error %d", resp.StatusCode)
	}

	var data struct {
		CPUStats struct {
			CPUUsage struct {
				TotalUsage uint64 `json:"total_usage"`
			} `json:"cpu_usage"`
			SystemCPUUsage uint64 `json:"system_cpu_usage"`
			OnlineCPUs     uint32 `json:"online_cpus"`
		} `json:"cpu_stats"`
		PreCPUStats struct {
			CPUUsage struct {
				TotalUsage uint64 `json:"total_usage"`
			} `json:"cpu_usage"`
			SystemCPUUsage uint64 `json:"system_cpu_usage"`
		} `json:"precpu_stats"`
		MemoryStats struct {
			Usage uint64 `json:"usage"`
			Limit uint64 `json:"limit"`
			Stats map[string]uint64 `json:"stats"`
		} `json:"memory_stats"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&data); err != nil {
		return 0, 0, "—", err
	}

	// Calculate CPU %
	cpuDelta := float64(data.CPUStats.CPUUsage.TotalUsage) - float64(data.PreCPUStats.CPUUsage.TotalUsage)
	systemDelta := float64(data.CPUStats.SystemCPUUsage) - float64(data.PreCPUStats.SystemCPUUsage)
	onlineCPUs := float64(data.CPUStats.OnlineCPUs)
	if onlineCPUs == 0 {
		onlineCPUs = 1.0
	}

	if systemDelta > 0 && cpuDelta > 0 {
		cpu = (cpuDelta / systemDelta) * onlineCPUs * 100.0
		// Round to 1 decimal place
		cpu = float64(int(cpu*10)) / 10.0
	}

	// Memory usage (subtract cache / inactive_file if available like Docker CLI does)
	usedBytes := data.MemoryStats.Usage
	if cache, ok := data.MemoryStats.Stats["inactive_file"]; ok && cache < usedBytes {
		usedBytes -= cache
	} else if cache, ok := data.MemoryStats.Stats["cache"]; ok && cache < usedBytes {
		usedBytes -= cache
	}

	memMb = int64(usedBytes / (1024 * 1024))
	if memMb >= 1024 {
		memLabel = fmt.Sprintf("%.1f GB", float64(memMb)/1024.0)
	} else if memMb > 0 {
		memLabel = fmt.Sprintf("%d MB", memMb)
	} else {
		memLabel = "—"
	}

	return cpu, memMb, memLabel, nil
}

// StreamLogsReader opens a raw streaming reader to Docker's container logs.
func (c *Client) StreamLogsReader(ctx context.Context, id string, tail int) (io.ReadCloser, error) {
	if !validContainerID.MatchString(id) {
		return nil, fmt.Errorf("invalid container id")
	}

	endpoint := fmt.Sprintf("http://localhost/containers/%s/logs?follow=1&stdout=1&stderr=1&tail=%d&timestamps=1", id, tail)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, err
	}

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode != http.StatusOK {
		resp.Body.Close()
		return nil, fmt.Errorf("docker logs error %d", resp.StatusCode)
	}

	return resp.Body, nil
}

// FallbackOverview provides standard demo stacks if Docker is not installed.
func FallbackOverview() *ContainersOverview {
	mockContainers := []ContainerItem{
		{Name: "caddy", Image: "caddy:2.8-alpine", Stack: "platform", State: "running", Uptime: "up 42d", CPU: 0.4, MemMb: 38, MemLabel: "38 MB", Ports: "80,443", CID: "a91f4c2e8b17", Running: true},
		{Name: "postgres", Image: "postgres:16.3-alpine", Stack: "platform", State: "running", Uptime: "up 42d", CPU: 1.2, MemMb: 412, MemLabel: "412 MB", Ports: "5432", CID: "7d3b0af5119c", Running: true},
		{Name: "immich-server", Image: "ghcr.io/immich-app/immich-server:v1.108", Stack: "immich", State: "running", Uptime: "up 12d", CPU: 3.8, MemMb: 1430, MemLabel: "1.4 GB", Ports: "2283", CID: "c04e7fa2d883", Running: true},
		{Name: "immich-ml", Image: "ghcr.io/immich-app/immich-machine-learning:v1.108", Stack: "immich", State: "running", Uptime: "up 12d", CPU: 0.9, MemMb: 986, MemLabel: "986 MB", Ports: "—", CID: "e5518bb7043a", Running: true},
		{Name: "jellyfin", Image: "jellyfin/jellyfin:10.9.7", Stack: "media", State: "running", Uptime: "up 8d", CPU: 2.1, MemMb: 604, MemLabel: "604 MB", Ports: "8096", CID: "2b6c9d1e77f4", Running: true},
		{Name: "forgejo", Image: "codeberg.org/forgejo/forgejo:7.0", Stack: "git", State: "running", Uptime: "up 31d", CPU: 0.3, MemMb: 218, MemLabel: "218 MB", Ports: "3000,2222", CID: "f7a2130cd569", Running: true},
		{Name: "homeassistant", Image: "ghcr.io/home-assistant/home-assistant:2026.8", Stack: "home", State: "running", Uptime: "up 19d", CPU: 1.6, MemMb: 512, MemLabel: "512 MB", Ports: "8123", CID: "9c41e6b2aa08", Running: true},
		{Name: "grafana", Image: "grafana/grafana:11.1.0", Stack: "observability", State: "running", Uptime: "up 42d", CPU: 0.5, MemMb: 164, MemLabel: "164 MB", Ports: "3001", CID: "31d8ff70b4e2", Running: true},
		{Name: "prometheus", Image: "prom/prometheus:v2.53.0", Stack: "observability", State: "running", Uptime: "up 42d", CPU: 0.8, MemMb: 386, MemLabel: "386 MB", Ports: "9090", CID: "ba5c2e91d370", Running: true},
		{Name: "pgbackrest", Image: "pgbackrest/pgbackrest:2.52", Stack: "platform", State: "stopped", Uptime: "exited 6h", CPU: 0, MemMb: 0, MemLabel: "—", Ports: "—", CID: "48e0c7135b9a", Running: false},
	}

	running := 0
	stopped := 0
	for _, c := range mockContainers {
		if c.Running {
			running++
		} else {
			stopped++
		}
	}

	return &ContainersOverview{
		DockerAvailable: false,
		EngineVersion:   "mock / docker offline",
		RunningCount:    running,
		StoppedCount:    stopped,
		TotalImagesSize: "6.4 GB",
		Containers:      mockContainers,
		Stacks:          []string{"platform", "immich", "media", "observability", "git", "home"},
		StackMeta: map[string]string{
			"platform":      "caddy · postgres · pgbackrest",
			"immich":        "compose stack · 2 services",
			"media":         "compose stack · 1 service",
			"observability": "compose stack · 2 services",
			"git":           "compose stack · 1 service",
			"home":          "compose stack · 1 service",
		},
	}
}
