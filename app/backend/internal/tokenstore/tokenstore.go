// Package tokenstore persists per-device auth token hashes, replacing the
// old single-shared-token model (one token_hash in config.yaml) with one
// entry per paired device. Only hashes are ever written to disk, same
// discipline as the legacy token_hash field.
package tokenstore

import (
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"syscall"
	"time"
)

type Entry struct {
	Name      string    `json:"name"`
	HashHex   string    `json:"hash"`
	CreatedAt time.Time `json:"created_at"`
}

// Store is not safe for concurrent writers - archangeld only ever writes
// from the one-shot `pair` CLI subcommand, never from the long-running
// server process, so this doesn't need locking.
type Store struct {
	path    string
	entries []Entry
}

// Load reads the store at path, or returns an empty store if the file
// doesn't exist yet (the common case before the first device is paired).
func Load(path string) (*Store, error) {
	s := &Store{path: path}

	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return s, nil
	}
	if err != nil {
		return nil, fmt.Errorf("reading token store %s: %w", path, err)
	}

	if err := json.Unmarshal(data, &s.entries); err != nil {
		return nil, fmt.Errorf("parsing token store %s: %w", path, err)
	}
	return s, nil
}

// Entries returns the currently paired devices. Used only to decide
// whether any auth token exists at all yet, not for anything security
// sensitive.
func (s *Store) Entries() []Entry {
	return s.entries
}

// IsValid reports whether hashHex matches any paired device's token hash,
// using a constant-time comparison per entry so timing can't leak how
// close a guess got.
func (s *Store) IsValid(hashHex string) bool {
	for _, e := range s.entries {
		if subtle.ConstantTimeCompare([]byte(e.HashHex), []byte(hashHex)) == 1 {
			return true
		}
	}
	return false
}

// Add appends a new device entry and persists the store immediately.
func (s *Store) Add(name, hashHex string) error {
	s.entries = append(s.entries, Entry{Name: name, HashHex: hashHex, CreatedAt: time.Now().UTC()})
	return s.save()
}

func (s *Store) save() error {
	data, err := json.MarshalIndent(s.entries, "", "  ")
	if err != nil {
		return fmt.Errorf("encoding token store: %w", err)
	}

	dir := filepath.Dir(s.path)
	if err := os.MkdirAll(dir, 0o750); err != nil {
		return fmt.Errorf("creating token store dir: %w", err)
	}

	// Write to a temp file and rename over the real path so a crash
	// mid-write can never leave a truncated/corrupt store behind.
	tmp := s.path + ".tmp"
	// 0640 (not 0600): `archangeld pair` runs as root (via sudo), but the
	// long-running server process runs as the unprivileged `archangel`
	// system user - a root-only file would be unreadable to it, which is
	// exactly what happened on real hardware (server failed to start with
	// "permission denied" after the first `pair` call). Group-readable,
	// plus chownGroupToMatch below matching the parent directory's group
	// (deploy.sh sets that to the `archangel` group), lets the service
	// read this without making it world-readable.
	if err := os.WriteFile(tmp, data, 0o640); err != nil {
		return fmt.Errorf("writing token store: %w", err)
	}
	if err := chownGroupToMatch(tmp, dir); err != nil {
		_ = os.Remove(tmp)
		return fmt.Errorf("setting token store group ownership: %w", err)
	}
	if err := os.Rename(tmp, s.path); err != nil {
		return fmt.Errorf("saving token store: %w", err)
	}
	return nil
}

// chownGroupToMatch sets path's group ownership to match dir's, leaving
// the owner (uid) untouched. When `pair` runs via sudo, that owner stays
// root - fine, since group-read (0640) is what the archangeld service
// actually needs. A no-op, non-fatal warning path on non-Unix platforms
// doesn't apply here: this package only ever runs on the Linux server.
func chownGroupToMatch(path, dir string) error {
	info, err := os.Stat(dir)
	if err != nil {
		return fmt.Errorf("stat %s: %w", dir, err)
	}
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok {
		return fmt.Errorf("could not read %s's group ownership", dir)
	}
	if err := os.Chown(path, -1, int(stat.Gid)); err != nil {
		return fmt.Errorf("chown %s to group %d: %w", path, stat.Gid, err)
	}
	return nil
}
