package system

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestMetricsHandler(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/api/v1/system/metrics", nil)
	rec := httptest.NewRecorder()

	MetricsHandler(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d", rec.Code)
	}

	var res SystemMetrics
	if err := json.Unmarshal(rec.Body.Bytes(), &res); err != nil {
		t.Fatalf("failed unmarshaling metrics response: %v", err)
	}

	if len(res.CPU.Cores) == 0 {
		t.Fatalf("expected at least 1 core reported")
	}
	if res.Memory.TotalBytes == 0 {
		t.Fatalf("expected memory total to be > 0")
	}
}

func TestProcessesHandler(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/api/v1/system/processes", nil)
	rec := httptest.NewRecorder()

	ProcessesHandler(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d", rec.Code)
	}

	var res ProcessListResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &res); err != nil {
		t.Fatalf("failed unmarshaling processes response: %v", err)
	}

	if res.TotalCount == 0 {
		t.Fatalf("expected total_count > 0")
	}
}
