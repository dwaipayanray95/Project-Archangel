package devops

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// ListDeployments searches for deployment scripts in /srv/deploy or git hooks.
func ListDeployments() ([]DeploymentItem, error) {
	var items []DeploymentItem

	deployDirs := []string{"/srv/deploy", "/srv/scripts", "/var/scripts"}
	for _, dir := range deployDirs {
		entries, err := os.ReadDir(dir)
		if err != nil {
			continue
		}

		for _, e := range entries {
			if e.IsDir() {
				continue
			}
			name := e.Name()
			if strings.HasSuffix(name, ".sh") || strings.HasPrefix(name, "deploy-") {
				finfo, _ := e.Info()
				mtime := "recently"
				if finfo != nil {
					mtime = finfo.ModTime().Format("Jan 02 15:04")
				}
				items = append(items, DeploymentItem{
					Name:     name,
					Target:   filepath.Join(dir, name),
					LastRun:  mtime,
					Duration: "—",
					Status:   "idle",
					Meta:     "script at " + filepath.Join(dir, name),
					Ok:       true,
					Actions:  []string{"Run"},
				})
			}
		}
	}

	return items, nil
}

// RunDeployment executes a deployment script safely with timeout.
func RunDeployment(name string) (string, error) {
	cleanName := filepath.Base(name)
	if !validUnitName.MatchString(cleanName) || !strings.HasSuffix(cleanName, ".sh") {
		return "", fmt.Errorf("invalid deployment script filename")
	}

	deployDirs := []string{"/srv/deploy", "/srv/scripts", "/var/scripts"}

	var scriptPath string
	for _, dir := range deployDirs {
		p := filepath.Join(dir, cleanName)
		if _, err := os.Stat(p); err == nil {
			scriptPath = p
			break
		}
	}

	if scriptPath == "" {
		return "", fmt.Errorf("deployment script not found: %s", cleanName)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	defer cancel()

	// Cap captured output so a runaway or malicious script can't exhaust
	// archangeld's memory (the full buffer is held in-process, then
	// re-serialized into the HTTP response and rendered whole in the app).
	const maxOutput = 256 * 1024
	var buf boundedBuffer
	buf.limit = maxOutput
	cmd := exec.CommandContext(ctx, "/bin/sh", scriptPath)
	cmd.Stdout = &buf
	cmd.Stderr = &buf
	err := cmd.Run()
	out := buf.String()
	if err != nil {
		return out, fmt.Errorf("script failed: %v: %s", err, out)
	}

	return out, nil
}

// boundedBuffer is an io.Writer that keeps only the first `limit` bytes
// written to it, discarding the rest (with a trailing marker) rather than
// growing without bound.
type boundedBuffer struct {
	buf       strings.Builder
	limit     int
	truncated bool
}

func (b *boundedBuffer) Write(p []byte) (int, error) {
	n := len(p)
	if !b.truncated {
		remaining := b.limit - b.buf.Len()
		if remaining <= 0 {
			b.truncated = true
		} else {
			if len(p) > remaining {
				p = p[:remaining]
				b.truncated = true
			}
			b.buf.Write(p)
		}
	}
	return n, nil
}

func (b *boundedBuffer) String() string {
	if b.truncated {
		return b.buf.String() + "\n... (output truncated)"
	}
	return b.buf.String()
}
