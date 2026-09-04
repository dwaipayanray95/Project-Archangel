package files

import (
	"encoding/json"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// ListHandler handles GET /api/v1/files/list?path=...
func ListHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	targetPath := r.URL.Query().Get("path")
	if targetPath == "" {
		targetPath = "/"
	}

	listing, err := ListDirectory(targetPath)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusForbidden)
		_ = json.NewEncoder(w).Encode(listing)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(listing)
}

// ReadHandler handles GET /api/v1/files/read?path=...&lines=...
func ReadHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	targetPath := r.URL.Query().Get("path")
	if targetPath == "" {
		http.Error(w, "path parameter required", http.StatusBadRequest)
		return
	}

	linesLimit := 300
	if lStr := r.URL.Query().Get("lines"); lStr != "" {
		if val, err := strconv.Atoi(lStr); err == nil && val > 0 {
			linesLimit = val
		}
	}

	content, err := ReadFilePreview(targetPath, linesLimit)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(content)
}

// DownloadHandler handles GET /api/v1/files/download?path=...
func DownloadHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	targetPath, err := resolvePath(r.URL.Query().Get("path"))
	if err != nil {
		http.Error(w, err.Error(), http.StatusForbidden)
		return
	}
	info, err := os.Stat(targetPath)
	if err != nil {
		http.Error(w, "file not found", http.StatusNotFound)
		return
	}
	if info.IsDir() {
		http.Error(w, "cannot download directory", http.StatusBadRequest)
		return
	}

	f, err := os.Open(targetPath)
	if err != nil {
		http.Error(w, err.Error(), http.StatusForbidden)
		return
	}
	defer f.Close()

	cleanName := strings.ReplaceAll(filepath.Base(targetPath), "\"", "_")
	cleanName = strings.ReplaceAll(cleanName, "\r", "")
	cleanName = strings.ReplaceAll(cleanName, "\n", "")

	w.Header().Set("Content-Disposition", "attachment; filename=\""+cleanName+"\"")
	w.Header().Set("Content-Type", "application/octet-stream")
	w.Header().Set("Content-Length", strconv.FormatInt(info.Size(), 10))

	_, _ = io.Copy(w, f)
}
