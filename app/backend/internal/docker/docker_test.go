package docker_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/dwaipayanray95/project-archangel/backend/internal/docker"
)

func init() {
	// Force the fallback/demo path regardless of whether the machine
	// running these tests happens to have a live Docker daemon at the
	// default socket path (true on GitHub Actions' ubuntu-latest runners).
	docker.SetDefaultClient(docker.NewClient("/nonexistent/docker.sock"))
}

func TestContainersHandlerFallback(t *testing.T) {
	req := httptest.NewRequest("GET", "/api/v1/docker/containers", nil)
	rec := httptest.NewRecorder()

	docker.ContainersHandler(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d", rec.Code)
	}

	var overview docker.ContainersOverview
	if err := json.Unmarshal(rec.Body.Bytes(), &overview); err != nil {
		t.Fatalf("failed decoding json: %v", err)
	}

	if overview.DockerAvailable {
		t.Errorf("expected DockerAvailable=false in fallback, got true")
	}

	if overview.RunningCount != 0 || overview.StoppedCount != 0 {
		t.Errorf("expected 0 running/stopped in fallback, got %d/%d", overview.RunningCount, overview.StoppedCount)
	}
}

func TestContainerActionHandler(t *testing.T) {
	req := httptest.NewRequest("POST", "/api/v1/docker/containers/caddy/restart", nil)
	req.SetPathValue("id", "caddy")
	req.SetPathValue("action", "restart")
	rec := httptest.NewRecorder()

	docker.ContainerActionHandler(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d", rec.Code)
	}

	var res docker.ActionResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &res); err != nil {
		t.Fatalf("failed decoding json: %v", err)
	}

	if !res.Success {
		t.Errorf("expected success, got false: %s", res.Message)
	}
}

func TestContainerActionHandlerRemove(t *testing.T) {
	req := httptest.NewRequest("POST", "/api/v1/docker/containers/redis/remove", nil)
	req.SetPathValue("id", "redis")
	req.SetPathValue("action", "remove")
	rec := httptest.NewRecorder()

	docker.ContainerActionHandler(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d", rec.Code)
	}

	var res docker.ActionResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &res); err != nil {
		t.Fatalf("failed decoding json: %v", err)
	}

	if !res.Success {
		t.Errorf("expected success, got false: %s", res.Message)
	}
}

func TestContainerCreateHandler(t *testing.T) {
	body := `{"image":"nginx:alpine","name":"test-web","ports":["8080:80"],"restart":"unless-stopped"}`
	req := httptest.NewRequest("POST", "/api/v1/docker/containers/run", strings.NewReader(body))
	rec := httptest.NewRecorder()

	docker.ContainerCreateHandler(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d", rec.Code)
	}

	var res docker.ActionResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &res); err != nil {
		t.Fatalf("failed decoding json: %v", err)
	}

	if !res.Success {
		t.Errorf("expected success, got false: %s", res.Message)
	}
}
