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
	if err := SetRoot(tmpDir); err != nil {
		t.Fatal(err)
	}

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
	if err := SetRoot(tmpDir); err != nil {
		t.Fatal(err)
	}
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

// TestJailRejectsEscapes is the regression test for the real bug this
// package shipped with: CleanPath alone (Clean + force-absolute) never
// confined anything to a root, so any paired device could read/download
// any file on the server. resolvePath (used by every list/read/download
// entrypoint) must reject both textual escapes (../, an absolute path
// outside root) and a symlink that lives inside root but points outside
// it.
func TestJailRejectsEscapes(t *testing.T) {
	root := t.TempDir()
	if err := SetRoot(root); err != nil {
		t.Fatal(err)
	}

	secretDir := t.TempDir() // a sibling of root, standing in for e.g. /etc
	secretFile := filepath.Join(secretDir, "shadow")
	if err := os.WriteFile(secretFile, []byte("root:x:0:0"), 0o600); err != nil {
		t.Fatal(err)
	}

	allowedFile := filepath.Join(root, "notes.txt")
	if err := os.WriteFile(allowedFile, []byte("hello"), 0o644); err != nil {
		t.Fatal(err)
	}

	// Sanity check: a path genuinely inside root still works.
	if _, err := resolvePath(allowedFile); err != nil {
		t.Fatalf("resolvePath rejected an in-root path: %v", err)
	}

	// Textual escape: an absolute path to a file entirely outside root.
	if _, err := resolvePath(secretFile); err == nil {
		t.Fatalf("resolvePath allowed an absolute path outside root: %s", secretFile)
	}

	// Textual escape via ../.
	traversal := filepath.Join(root, "..", filepath.Base(secretDir), "shadow")
	if _, err := resolvePath(traversal); err == nil {
		t.Fatalf("resolvePath allowed a ../ escape: %s", traversal)
	}

	// Symlink escape: the link itself lives inside root, but its target
	// does not - this must be rejected even though the requested path
	// string is textually within root.
	linkPath := filepath.Join(root, "leaked")
	if err := os.Symlink(secretFile, linkPath); err != nil {
		t.Fatal(err)
	}
	if _, err := resolvePath(linkPath); err == nil {
		t.Fatalf("resolvePath allowed a symlink escaping root: %s -> %s", linkPath, secretFile)
	}

	// And ListDirectory must mark that same symlink as broken/unusable
	// rather than presenting it as a normal, followable entry.
	listing, err := ListDirectory(root)
	if err != nil {
		t.Fatalf("ListDirectory failed: %v", err)
	}
	found := false
	for _, e := range listing.Entries {
		if e.Name == "leaked" {
			found = true
			if !e.IsBroken {
				t.Errorf("expected the escaping symlink to be marked IsBroken, got %+v", e)
			}
		}
	}
	if !found {
		t.Fatal("expected to find the 'leaked' symlink in the listing")
	}
}

// TestListHandlerDefaultsEmptyPathToRoot is the regression test for a
// real bug found on real hardware: the app's first-ever load requests
// path="" (its landing state before the user has navigated anywhere),
// and ListHandler used to default that to "/" - which almost never
// falls inside files_root, so the very first screen a user saw after
// configuring files_root was a 403.
func TestListHandlerDefaultsEmptyPathToRoot(t *testing.T) {
	tmpDir := t.TempDir()
	if err := SetRoot(tmpDir); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(tmpDir, "welcome.txt"), []byte("hi"), 0o644); err != nil {
		t.Fatal(err)
	}

	req := httptest.NewRequest("GET", "/api/v1/files/list", nil) // no ?path= at all
	rec := httptest.NewRecorder()
	ListHandler(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 for an empty path, got %d: %s", rec.Code, rec.Body.String())
	}
	var listing DirectoryListing
	if err := json.Unmarshal(rec.Body.Bytes(), &listing); err != nil {
		t.Fatal(err)
	}
	if listing.TotalEntries != 1 || listing.Entries[0].Name != "welcome.txt" {
		t.Errorf("expected the empty path to land on files_root itself, got %+v", listing)
	}
}

// TestEmptyRootRejectsEverything is the fail-closed check: an
// unconfigured files_root must disable the browser entirely, not
// default to allowing everything (which is exactly the bug this jail
// fixes).
func TestEmptyRootRejectsEverything(t *testing.T) {
	if err := SetRoot(""); err != nil {
		t.Fatal(err)
	}
	if _, err := resolvePath("/etc/passwd"); err == nil {
		t.Fatal("expected resolvePath to reject everything when root is unset")
	}
}
