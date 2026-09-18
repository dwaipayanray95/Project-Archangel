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

var defaultDeployDirs = []string{"/srv/deploy", "/srv/scripts", "/var/scripts"}

func getDeployDirs() []string {
	dirs := []string{}
	if custom := os.Getenv("ARCHANGEL_DEPLOY_DIR"); custom != "" {
		dirs = append(dirs, custom)
	}
	dirs = append(dirs, defaultDeployDirs...)
	tempDeploy := filepath.Join(os.TempDir(), "archangel-deploy")
	dirs = append(dirs, tempDeploy)
	return dirs
}

// ListDeployments searches for deployment scripts in /srv/deploy or git hooks.
func ListDeployments() ([]DeploymentItem, error) {
	items := make([]DeploymentItem, 0)
	seen := make(map[string]bool)

	for _, dir := range getDeployDirs() {
		entries, err := os.ReadDir(dir)
		if err != nil {
			continue
		}

		for _, e := range entries {
			if e.IsDir() {
				continue
			}
			name := e.Name()
			if seen[name] {
				continue
			}
			if strings.HasSuffix(name, ".sh") || strings.HasPrefix(name, "deploy-") {
				seen[name] = true
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
					Actions:  []string{"Run", "Edit", "Delete"},
				})
			}
		}
	}

	return items, nil
}

func validateScriptName(name string) error {
	if strings.Contains(name, "/") || strings.Contains(name, "\\") || name != filepath.Base(name) {
		return fmt.Errorf("invalid deployment script filename: directory separators not allowed")
	}
	if !validUnitName.MatchString(name) || !strings.HasSuffix(name, ".sh") {
		return fmt.Errorf("invalid deployment script filename (must end with .sh and contain only safe alphanumeric characters)")
	}
	return nil
}

// CreateOrUpdateDeployment creates or updates a deployment script in /srv/deploy.
func CreateOrUpdateDeployment(name string, content string) error {
	if err := validateScriptName(name); err != nil {
		return err
	}

	dirs := getDeployDirs()
	var targetDir string
	for _, dir := range dirs {
		if _, err := os.Stat(dir); err == nil {
			targetDir = dir
			break
		}
	}

	if targetDir == "" {
		primary := dirs[0]
		if err := os.MkdirAll(primary, 0755); err == nil {
			targetDir = primary
		} else {
			fallback := filepath.Join(os.TempDir(), "archangel-deploy")
			_ = os.MkdirAll(fallback, 0755)
			targetDir = fallback
		}
	}

	targetPath := filepath.Join(targetDir, name)
	if err := os.WriteFile(targetPath, []byte(content), 0755); err != nil {
		return fmt.Errorf("failed to write deployment script: %w", err)
	}
	return nil
}

// GetDeploymentContent reads the source code of a deployment script.
func GetDeploymentContent(name string) (string, error) {
	if err := validateScriptName(name); err != nil {
		return "", err
	}

	for _, dir := range getDeployDirs() {
		p := filepath.Join(dir, name)
		if data, err := os.ReadFile(p); err == nil {
			return string(data), nil
		}
	}
	return "", fmt.Errorf("deployment script not found: %s", name)
}

// DeleteDeployment removes a deployment script.
func DeleteDeployment(name string) error {
	if err := validateScriptName(name); err != nil {
		return err
	}

	deleted := false
	for _, dir := range getDeployDirs() {
		p := filepath.Join(dir, name)
		if _, err := os.Stat(p); err == nil {
			if err := os.Remove(p); err == nil {
				deleted = true
			}
		}
	}
	if !deleted {
		return fmt.Errorf("deployment script not found or could not be removed: %s", name)
	}
	return nil
}

// RunDeployment executes a deployment script safely with timeout.
func RunDeployment(name string) (string, error) {
	if err := validateScriptName(name); err != nil {
		return "", err
	}

	var scriptPath string
	for _, dir := range getDeployDirs() {
		p := filepath.Join(dir, name)
		if _, err := os.Stat(p); err == nil {
			scriptPath = p
			break
		}
	}

	if scriptPath == "" {
		return "", fmt.Errorf("deployment script not found: %s", name)
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
