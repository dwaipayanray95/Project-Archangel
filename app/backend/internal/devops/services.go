package devops

import (
	"bufio"
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"runtime"
	"strings"
	"time"
)

var validUnitName = regexp.MustCompile(`^[a-zA-Z0-9@_.:-]+$`)

// managedUnits is the fixed allowlist of systemd units this app is allowed
// to inspect and act on. ServiceAction/TriggerScheduled must only ever
// target something in this set - without it, any string matching
// validUnitName's charset (which permits arbitrary unit names, including
// ssh.service or archangeld.service itself) would be handed straight to
// `systemctl <action> <name>`, turning "manage a few homelab services" into
// "manage anything on the box."
var managedUnits = map[string]bool{
	"caddy.service":               true,
	"docker.service":              true,
	"postgresql.service":          true,
	"wg-quick@wg0.service":        true,
	"archangeld.service":          true,
	"unattended-upgrades.service": true,
	"ssh.service":                 true,
	"cron.service":                true,
}

// ListServices inspects systemd service units.
func ListServices() ([]ServiceItem, error) {
	if runtime.GOOS != "linux" {
		return listLocalFallbackServices()
	}

	// Check if systemctl binary exists
	systemctl, err := exec.LookPath("systemctl")
	if err != nil {
		return listLocalFallbackServices()
	}

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	// List targeted services or common homelab units
	units := managedUnitNames()

	cmd := exec.CommandContext(ctx, systemctl, append([]string{"show", "--property=Id,Description,LoadState,ActiveState,SubState,ActiveEnterTimestamp"}, units...)...)
	out, err := cmd.Output()
	if err != nil {
		return listLocalFallbackServices()
	}

	return parseSystemctlShow(string(out)), nil
}

func parseSystemctlShow(raw string) []ServiceItem {
	var items []ServiceItem
	scanner := bufio.NewScanner(strings.NewReader(raw))

	current := ServiceItem{}
	activeTs := ""

	flush := func() {
		if current.Name != "" && current.LoadState != "not-found" {
			current.Ok = current.ActiveState == "active"
			current.Status = current.ActiveState
			if current.Status == "" {
				current.Status = "unknown"
			}

			metaParts := []string{current.SubState}
			if activeTs != "" {
				metaParts = append(metaParts, "since "+activeTs)
			}
			current.Meta = strings.Join(metaParts, " · ")

			if current.Ok {
				current.Actions = []string{"Restart", "Stop", "Logs"}
			} else {
				current.Actions = []string{"Start", "Logs"}
			}
			items = append(items, current)
		}
		current = ServiceItem{}
		activeTs = ""
	}

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			flush()
			continue
		}

		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}
		k, v := parts[0], parts[1]

		switch k {
		case "Id":
			current.Name = v
		case "Description":
			current.Description = v
		case "LoadState":
			current.LoadState = v
		case "ActiveState":
			current.ActiveState = v
		case "SubState":
			current.SubState = v
		case "ActiveEnterTimestamp":
			if v != "" {
				activeTs = v
				// Abbreviate if too long (e.g. Fri 2026-09-11 12:00:00 UTC)
				if len(activeTs) > 25 {
					activeTs = activeTs[:25]
				}
			}
		}
	}
	flush()

	if len(items) == 0 {
		fallback, _ := listLocalFallbackServices()
		return fallback
	}
	return items
}

// managedUnitNames returns managedUnits' keys.
func managedUnitNames() []string {
	names := make([]string, 0, len(managedUnits))
	for name := range managedUnits {
		names = append(names, name)
	}
	return names
}

// ServiceAction triggers systemctl start, stop, or restart.
func ServiceAction(name, action string) error {
	if !validUnitName.MatchString(name) || !managedUnits[name] {
		return fmt.Errorf("invalid service name")
	}

	switch action {
	case "start", "stop", "restart":
	default:
		return fmt.Errorf("unsupported action: %s", action)
	}

	if runtime.GOOS != "linux" {
		return nil // Simulated on non-Linux dev machines
	}

	systemctl, err := exec.LookPath("systemctl")
	if err != nil {
		return fmt.Errorf("systemctl not available on this host")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, systemctl, action, name)
	var errBuf bytes.Buffer
	cmd.Stderr = &errBuf

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("%s failed: %v (%s)", action, err, strings.TrimSpace(errBuf.String()))
	}
	return nil
}

// listLocalFallbackServices inspects standard service files or daemon presence.
func listLocalFallbackServices() ([]ServiceItem, error) {
	// Detect if Docker or Archangel is running on this machine
	dockerActive := false
	if _, err := os.Stat("/var/run/docker.sock"); err == nil {
		dockerActive = true
	}

	return []ServiceItem{
		{
			Name:        "docker.service",
			Description: "Docker Application Container Engine",
			ActiveState: func() string {
				if dockerActive {
					return "active"
				}
				return "inactive"
			}(),
			Status: func() string {
				if dockerActive {
					return "active"
				}
				return "inactive"
			}(),
			Ok:      dockerActive,
			Meta:    "local daemon socket check",
			Actions: []string{"Restart", "Logs"},
		},
		{
			Name:        "archangeld.service",
			Description: "Archangel Host Control Daemon",
			ActiveState: "active",
			Status:      "active",
			Ok:          true,
			Meta:        "current daemon instance",
			Actions:     []string{"Restart", "Logs"},
		},
	}, nil
}
