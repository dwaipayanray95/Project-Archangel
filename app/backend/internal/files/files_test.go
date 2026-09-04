package files

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestCleanPath(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"", "/"},
		{"/", "/"},
		{"/var/log", "/var/log"},
		{"/var/../etc", "/etc"},
		{"etc/passwd", "/etc/passwd"},
		{"/foo/bar/../../", "/"},
	}

	for _, tc := range tests {
		got := CleanPath(tc.input)
		if got != tc.expected {
			t.Errorf("CleanPath(%q) = %q; want %q", tc.input, got, tc.expected)
		}
	}
}

func TestListDirectoryAndReadFile(t *testing.T) {
	// Create temporary directory structure
	tmpDir := t.TempDir()

	subDir := filepath.Join(tmpDir, "subfolder")
	if err := os.Mkdir(subDir, 0755); err != nil {
		t.Fatal(err)
	}

	testFile := filepath.Join(tmpDir, "sample.txt")
	content := "Line 1: Hello\nLine 2: Archangel\nLine 3: Real files\n"
	if err := os.WriteFile(testFile, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}

	logFile := filepath.Join(tmpDir, "service.log")
	if err := os.WriteFile(logFile, []byte("log event"), 0644); err != nil {
		t.Fatal(err)
	}

	// Test ListDirectory
	listing, err := ListDirectory(tmpDir)
	if err != nil {
		t.Fatalf("ListDirectory failed: %v", err)
	}

	if listing.TotalEntries != 3 {
		t.Fatalf("expected 3 entries, got %d", listing.TotalEntries)
	}

	// Verify dirs come first
	if listing.Entries[0].Kind != "dir" || listing.Entries[0].Name != "subfolder" {
		t.Errorf("expected first entry to be dir 'subfolder', got %+v", listing.Entries[0])
	}

	// Verify log kind detection
	foundLog := false
	for _, e := range listing.Entries {
		if e.Name == "service.log" && e.Kind == "log" {
			foundLog = true
		}
	}
	if !foundLog {
		t.Errorf("expected service.log to be classified as log")
	}

	// Test ReadFilePreview
	preview, err := ReadFilePreview(testFile, 2)
	if err != nil {
		t.Fatalf("ReadFilePreview failed: %v", err)
	}

	if preview.Binary {
		t.Errorf("sample.txt should not be binary")
	}
	if len(preview.Lines) != 2 {
		t.Errorf("expected 2 lines with limit=2, got %d", len(preview.Lines))
	}
	if !preview.Truncated {
		t.Errorf("expected preview to be marked as truncated")
	}
}

func TestHandlers(t *testing.T) {
	tmpDir := t.TempDir()
	fpath := filepath.Join(tmpDir, "app.log")
	_ = os.WriteFile(fpath, []byte("error: connection timed out\n"), 0644)

	// Test ListHandler
	reqList := httptest.NewRequest("GET", "/api/v1/files/list?path="+tmpDir, nil)
	recList := httptest.NewRecorder()
	ListHandler(recList, reqList)

	if recList.Code != http.StatusOK {
		t.Fatalf("ListHandler returned status %d", recList.Code)
	}

	var listing DirectoryListing
	if err := json.Unmarshal(recList.Body.Bytes(), &listing); err != nil {
		t.Fatalf("failed decoding listing json: %v", err)
	}
	if listing.TotalEntries != 1 {
		t.Errorf("expected 1 entry, got %d", listing.TotalEntries)
	}

	// Test ReadHandler
	reqRead := httptest.NewRequest("GET", "/api/v1/files/read?path="+fpath, nil)
	recRead := httptest.NewRecorder()
	ReadHandler(recRead, reqRead)

	if recRead.Code != http.StatusOK {
		t.Fatalf("ReadHandler returned status %d", recRead.Code)
	}

	var fileResp FileContentResponse
	if err := json.Unmarshal(recRead.Body.Bytes(), &fileResp); err != nil {
		t.Fatalf("failed decoding read json: %v", err)
	}
	if len(fileResp.Lines) != 1 || fileResp.Lines[0] != "error: connection timed out" {
		t.Errorf("unexpected preview line: %v", fileResp.Lines)
	}
}
