package files

import (
	"bufio"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/user"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"syscall"
)

// root is the directory the file browser is jailed to (config.yaml's
// files_root). Set once at startup via SetRoot - see cmd/archangeld/main.go.
// Every entrypoint into this package (list/read/download) must resolve
// through resolvePath, which enforces this; CleanPath alone is cosmetic
// normalization only, not a security boundary.
var root string

// SetRoot configures the file browser's jail root. An empty root leaves
// the browser disabled (every request rejected) rather than defaulting
// to "/" - failing closed, since the whole point is that the file
// browser must never be able to reach outside a directory the operator
// explicitly chose (real incident: this was unset for a while and the
// browser could read anything on the box, including WireGuard/SSH
// private keys and every paired device's auth token hashes).
func SetRoot(r string) error {
	if r == "" {
		root = ""
		return nil
	}
	abs, err := filepath.Abs(r)
	if err != nil {
		return fmt.Errorf("resolving files_root %q: %w", r, err)
	}
	resolved, err := filepath.EvalSymlinks(abs)
	if err != nil {
		return fmt.Errorf("resolving files_root %q: %w", r, err)
	}
	root = resolved
	return nil
}

// Root returns the currently configured jail root ("" if unconfigured).
func Root() string {
	return root
}

// CleanPath resolves and sanitizes a path into an absolute, `.`/`..`-free
// form. Purely cosmetic normalization - NOT a security boundary on its
// own (it happily returns paths outside any root). Use resolvePath for
// anything that touches the filesystem.
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

// resolvePath validates that requested lies within the configured root,
// both textually and after resolving symlinks (a symlink *inside* root
// can still point outside it), and returns the real filesystem path to
// operate on.
func resolvePath(requested string) (string, error) {
	if root == "" {
		return "", fmt.Errorf("file browser is not configured - set files_root in config.yaml")
	}

	cleaned := CleanPath(requested)
	if !isWithinRoot(cleaned) {
		return "", fmt.Errorf("path is outside the configured files_root")
	}

	resolved, err := filepath.EvalSymlinks(cleaned)
	if err != nil {
		if os.IsNotExist(err) {
			// Let the caller's os.Stat/os.ReadDir surface a normal
			// not-found error rather than this masking it as a jail
			// violation.
			return cleaned, nil
		}
		return "", err
	}
	if !isWithinRoot(resolved) {
		return "", fmt.Errorf("path escapes files_root via a symlink")
	}
	return resolved, nil
}

func isWithinRoot(p string) bool {
	rel, err := filepath.Rel(root, p)
	if err != nil {
		return false
	}
	return rel == "." || (rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator)))
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

// uidCache/gidCache avoid resolving owner/group names via a syscall for
// every entry in every listing - same pattern as
// internal/system/processes.go's uidCache, kept local rather than
// shared since these are two small, otherwise-unrelated packages.
var (
	uidCacheMu sync.RWMutex
	uidCache   = make(map[string]string)
	gidCacheMu sync.RWMutex
	gidCache   = make(map[string]string)
)

func usernameFromUID(uidStr string) string {
	uidCacheMu.RLock()
	name, ok := uidCache[uidStr]
	uidCacheMu.RUnlock()
	if ok {
		return name
	}
	resolved := uidStr
	if u, err := user.LookupId(uidStr); err == nil && u.Username != "" {
		resolved = u.Username
	}
	uidCacheMu.Lock()
	uidCache[uidStr] = resolved
	uidCacheMu.Unlock()
	return resolved
}

func groupnameFromGID(gidStr string) string {
	gidCacheMu.RLock()
	name, ok := gidCache[gidStr]
	gidCacheMu.RUnlock()
	if ok {
		return name
	}
	resolved := gidStr
	if g, err := user.LookupGroupId(gidStr); err == nil && g.Name != "" {
		resolved = g.Name
	}
	gidCacheMu.Lock()
	gidCache[gidStr] = resolved
	gidCacheMu.Unlock()
	return resolved
}

// ListDirectory inspects a directory and returns its structured entries.
func ListDirectory(dirPath string) (*DirectoryListing, error) {
	clean, err := resolvePath(dirPath)
	if err != nil {
		return &DirectoryListing{
			Path:     CleanPath(dirPath),
			Parent:   filepath.Dir(CleanPath(dirPath)),
			Entries:  []FileEntry{},
			Readable: false,
			Error:    err.Error(),
		}, err
	}

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
	if clean == root {
		parent = root
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

		owner, group := "", ""
		if stat, ok := info.Sys().(*syscall.Stat_t); ok {
			owner = usernameFromUID(strconv.FormatUint(uint64(stat.Uid), 10))
			group = groupnameFromGID(strconv.FormatUint(uint64(stat.Gid), 10))
		}

		isBroken := false
		if info.IsDir() {
			kind = "dir"
			humanSize = "—"
		} else if info.Mode()&os.ModeSymlink != 0 {
			kind = "symlink"
			if t, err := os.Readlink(fullPath); err == nil {
				target = t
				// A symlink is only "not broken" if its resolved target
				// both exists AND stays within root - one pointing
				// outside root is treated the same as broken, since
				// following it must never be allowed either way.
				if resolvedTarget, err := filepath.EvalSymlinks(fullPath); err != nil || !isWithinRoot(resolvedTarget) {
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
			Owner:     owner,
			Group:     group,
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

// binarySniffWindow is how much of a file's head is scanned for null
// bytes before deciding it's binary - a text file could have its first
// 512 bytes look like plain text (the old window) but contain binary
// data shortly after (e.g. a log with an embedded core dump, or a
// misdetected format); scanning a larger window catches that without
// reading arbitrarily large files.
const binarySniffWindow = 64 * 1024

// ReadFilePreview reads up to maxLines (or maxBytes) of a file, detecting binary and special files.
func ReadFilePreview(filePath string, maxLines int) (*FileContentResponse, error) {
	clean, err := resolvePath(filePath)
	if err != nil {
		return nil, err
	}
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

	sniffBuf := make([]byte, binarySniffWindow)
	n, _ := io.ReadFull(f, sniffBuf)
	mimeSample := sniffBuf[:n]
	if len(mimeSample) > 512 {
		mimeSample = mimeSample[:512]
	}
	mimeType := http.DetectContentType(mimeSample)

	// Check if file is binary (either MIME or contains null bytes
	// anywhere in the sniffed window, not just the first 512 bytes).
	isBinary := false
	if !strings.HasPrefix(mimeType, "text/") &&
		!strings.Contains(mimeType, "json") &&
		!strings.Contains(mimeType, "xml") &&
		!strings.Contains(mimeType, "javascript") {
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
