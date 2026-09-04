package system

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
)

func TestUsernameFromUID_ConcurrentRace(t *testing.T) {
	const goroutines = 50
	const iterations = 100

	var wg sync.WaitGroup
	wg.Add(goroutines)

	for g := 0; g < goroutines; g++ {
		go func(id int) {
			defer wg.Done()
			for i := 0; i < iterations; i++ {
				uidStr := fmt.Sprintf("%d", (id*iterations+i)%20)
				_ = usernameFromUID(uidStr)
			}
		}(g)
	}

	wg.Wait()
}

func TestStatsWsHandler_OriginCheck(t *testing.T) {
	// Gorilla websocket default checkOrigin function:
	// If upgrader.CheckOrigin is nil, Upgrade calls gorilla's internal checkSameOrigin.
	// We test Upgrade directly via httptest.ResponseRecorder:

	// 1. Cross-origin request with hostile Origin should be rejected with 403 Forbidden
	reqCrossOrigin := httptest.NewRequest(http.MethodGet, "http://10.0.0.1:8080/ws/stats", nil)
	reqCrossOrigin.Header.Set("Connection", "upgrade")
	reqCrossOrigin.Header.Set("Upgrade", "websocket")
	reqCrossOrigin.Header.Set("Sec-WebSocket-Version", "13")
	reqCrossOrigin.Header.Set("Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ==")
	reqCrossOrigin.Header.Set("Origin", "https://malicious-site.com")
	reqCrossOrigin.Host = "10.0.0.1:8080"

	rec := httptest.NewRecorder()
	_, err := upgrader.Upgrade(rec, reqCrossOrigin, nil)
	if err == nil {
		t.Fatalf("expected error on cross-origin upgrade, got nil")
	}
	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected status 403 Forbidden on cross-origin upgrade, got %d", rec.Code)
	}

	// 2. Request with matching origin or no origin (Flutter app) is not rejected by CheckOrigin
	reqNoOrigin := httptest.NewRequest(http.MethodGet, "http://10.0.0.1:8080/ws/stats", nil)
	reqNoOrigin.Header.Set("Connection", "upgrade")
	reqNoOrigin.Header.Set("Upgrade", "websocket")
	reqNoOrigin.Header.Set("Sec-WebSocket-Version", "13")
	reqNoOrigin.Header.Set("Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ==")
	reqNoOrigin.Host = "10.0.0.1:8080"

	rec2 := httptest.NewRecorder()
	// Upgrade will attempt to hijack response; ResponseRecorder doesn't implement Hijacker
	// but checkSameOrigin runs BEFORE hijacking. If CheckOrigin failed, status would be 403.
	_, _ = upgrader.Upgrade(rec2, reqNoOrigin, nil)
	if rec2.Code == http.StatusForbidden {
		t.Fatalf("expected non-browser request to pass CheckOrigin, but got 403")
	}
}
