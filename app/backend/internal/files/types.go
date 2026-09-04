package files

import "time"

// FileEntry represents a single directory child with metadata.
type FileEntry struct {
	Name      string    `json:"name"`
	Path      string    `json:"path"`
	Kind      string    `json:"kind"` // "dir", "file", "symlink", "log"
	SizeBytes int64     `json:"size_bytes"`
	Size      string    `json:"size"` // Human-readable (e.g. "1.4 MB", "318 KB")
	Perms     string    `json:"perms"`
	ModTime   time.Time `json:"mod_time"`
	Mtime     string    `json:"mtime"` // Formatted date (e.g. "Sep 02 06:14")
	Owner     string    `json:"owner,omitempty"`
	Group     string    `json:"group,omitempty"`
	Target    string    `json:"target,omitempty"` // Target path if symlink
	IsBroken  bool      `json:"is_broken,omitempty"` // True if symlink points to non-existent target
}

// DirectoryListing contains directory contents and navigation context.
type DirectoryListing struct {
	Path         string      `json:"path"`
	Parent       string      `json:"parent"`
	Entries      []FileEntry `json:"entries"`
	TotalEntries int         `json:"total_entries"`
	Readable     bool        `json:"readable"`
	Error        string      `json:"error,omitempty"`
}

// FileContentResponse returns line-based file preview data.
type FileContentResponse struct {
	Path      string   `json:"path"`
	Name      string   `json:"name"`
	SizeBytes int64    `json:"size_bytes"`
	Lines     []string `json:"lines"`
	LineCount int      `json:"line_count"`
	Truncated bool     `json:"truncated"`
	Binary    bool     `json:"binary"`
	MimeType  string   `json:"mime_type"`
}
