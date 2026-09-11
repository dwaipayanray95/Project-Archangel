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

	cmd := exec.CommandContext(ctx, "/bin/sh", scriptPath)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return string(out), fmt.Errorf("script failed: %v: %s", err, string(out))
	}

	return string(out), nil
}
