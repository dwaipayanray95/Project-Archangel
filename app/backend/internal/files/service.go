package files

import (
	"bufio"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// CleanPath resolves and sanitizes a path, ensuring it is absolute and
// within standard filesystem roots.
func CleanPath(p string) string {
	if p == "" {
		return "/"
	}
	cleaned := filepath.Clean(p)
	if !filepath.IsAbs(cleaned) {
		cleaned = "/" + cleaned
	}
	return cleaned
}

// FormatBytes converts raw bytes to human-readable format.
func FormatBytes(b int64) string {
	const unit = 1024
	if b < unit {
		return fmt.Sprintf("%d B", b)
	}
	div, exp := int64(unit), 0
	for n := b / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(b)/float64(div), "KMGTPE"[exp])
}

// ListDirectory inspects a directory and returns its structured entries.
func ListDirectory(dirPath string) (*DirectoryListing, error) {
	clean := CleanPath(dirPath)

	entries, err := os.ReadDir(clean)
	if err != nil {
		return &DirectoryListing{
			Path:     clean,
			Parent:   filepath.Dir(clean),
			Entries:  []FileEntry{},
			Readable: false,
			Error:    err.Error(),
		}, err
	}

	parent := filepath.Dir(clean)
	if clean == "/" {
		parent = "/"
	}

	res := &DirectoryListing{
		Path:     clean,
		Parent:   parent,
		Entries:  make([]FileEntry, 0, len(entries)),
		Readable: true,
	}

	for _, e := range entries {
		fullPath := filepath.Join(clean, e.Name())
		info, err := e.Info()
		if err != nil {
			continue
		}

		kind := "file"
		perms := info.Mode().String()
		size := info.Size()
		humanSize := FormatBytes(size)
		target := ""

		isBroken := false
		if info.IsDir() {
			kind = "dir"
			humanSize = "—"
		} else if info.Mode()&os.ModeSymlink != 0 {
			kind = "symlink"
			if t, err := os.Readlink(fullPath); err == nil {
				target = t
				// Check if symlink target exists
				resolvedTarget := t
				if !filepath.IsAbs(resolvedTarget) {
					resolvedTarget = filepath.Join(clean, t)
				}
				if _, err := os.Stat(resolvedTarget); err != nil {
					isBroken = true
				}
			}
		} else if strings.HasSuffix(e.Name(), ".log") || strings.Contains(clean, "/var/log") {
			kind = "log"
		}

		res.Entries = append(res.Entries, FileEntry{
			Name:      e.Name(),
			Path:      fullPath,
			Kind:      kind,
			SizeBytes: size,
			Size:      humanSize,
			Perms:     perms,
			ModTime:   info.ModTime(),
			Mtime:     info.ModTime().Format("Jan 02 15:04"),
			Target:    target,
			IsBroken:  isBroken,
		})
	}

	// Sort directories first, then alphabetically
	sort.Slice(res.Entries, func(i, j int) bool {
		iIsDir := res.Entries[i].Kind == "dir"
		jIsDir := res.Entries[j].Kind == "dir"
		if iIsDir != jIsDir {
			return iIsDir // dirs first
		}
		return strings.ToLower(res.Entries[i].Name) < strings.ToLower(res.Entries[j].Name)
	})

	res.TotalEntries = len(res.Entries)
	return res, nil
}

// ReadFilePreview reads up to maxLines (or maxBytes) of a file, detecting binary and special files.
func ReadFilePreview(filePath string, maxLines int) (*FileContentResponse, error) {
	clean := CleanPath(filePath)
	info, err := os.Stat(clean)
	if err != nil {
		return nil, err
	}
	if info.IsDir() {
		return nil, fmt.Errorf("cannot preview directory")
	}
	if !info.Mode().IsRegular() {
		return nil, fmt.Errorf("cannot preview special device file or pipe")
	}

	f, err := os.Open(clean)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	// Sniff first 512 bytes for content type and binary detection
	sniffBuf := make([]byte, 512)
	n, _ := io.ReadFull(f, sniffBuf)
	mimeType := http.DetectContentType(sniffBuf[:n])

	// Check if file is binary (either MIME or contains null bytes)
	isBinary := false
	if !strings.HasPrefix(mimeType, "text/") &&
		!strings.Contains(mimeType, "json") &&
		!strings.Contains(mimeType, "xml") &&
		!strings.Contains(mimeType, "javascript") {
		// Verify if null bytes exist
		for _, b := range sniffBuf[:n] {
			if b == 0 {
				isBinary = true
				break
			}
		}
	}

	if isBinary {
		return &FileContentResponse{
			Path:      clean,
			Name:      filepath.Base(clean),
			SizeBytes: info.Size(),
			Lines:     []string{"(binary file cannot be previewed)"},
			LineCount: 0,
			Truncated: false,
			Binary:    true,
			MimeType:  mimeType,
		}, nil
	}

	// Reset read offset to start
	if _, err := f.Seek(0, io.SeekStart); err != nil {
		return nil, err
	}

	if maxLines <= 0 || maxLines > 2000 {
		maxLines = 500
	}

	var lines []string
	reader := bufio.NewReaderSize(f, 64*1024)
	truncated := false
	const maxLineDisplayLen = 2048 // Clamp extremely long single lines (e.g. minified code)

	for len(lines) < maxLines {
		lineBytes, isPrefix, err := reader.ReadLine()
		if err != nil {
			if err != io.EOF && len(lines) == 0 {
				return nil, err
			}
			break
		}

		lineStr := string(lineBytes)
		if len(lineStr) > maxLineDisplayLen {
			lineStr = lineStr[:maxLineDisplayLen] + " ... [line truncated]"
		}

		// If line was longer than buffer, discard remainder of this line
		if isPrefix {
			for {
				_, more, skipErr := reader.ReadLine()
				if !more || skipErr != nil {
					break
				}
			}
		}

		lines = append(lines, lineStr)
	}

	if len(lines) >= maxLines {
		truncated = true
	}

	return &FileContentResponse{
		Path:      clean,
		Name:      filepath.Base(clean),
		SizeBytes: info.Size(),
		Lines:     lines,
		LineCount: len(lines),
		Truncated: truncated,
		Binary:    false,
		MimeType:  mimeType,
	}, nil
}
