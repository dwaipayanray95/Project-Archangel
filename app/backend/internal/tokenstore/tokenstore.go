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

	if err := os.MkdirAll(filepath.Dir(s.path), 0o700); err != nil {
		return fmt.Errorf("creating token store dir: %w", err)
	}

	// Write to a temp file and rename over the real path so a crash
	// mid-write can never leave a truncated/corrupt store behind.
	tmp := s.path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return fmt.Errorf("writing token store: %w", err)
	}
	if err := os.Rename(tmp, s.path); err != nil {
		return fmt.Errorf("saving token store: %w", err)
	}
	return nil
}
