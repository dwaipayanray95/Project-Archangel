package devops

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

// ListScheduled inspects systemd timers and crontab jobs.
func ListScheduled() ([]ScheduledItem, error) {
	if runtime.GOOS != "linux" {
		return listLocalCron(), nil
	}

	systemctl, err := exec.LookPath("systemctl")
	if err != nil {
		return listLocalCron(), nil
	}

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, systemctl, "list-timers", "--all", "--no-pager")
	out, err := cmd.Output()
	if err != nil {
		return listLocalCron(), nil
	}

	items := parseSystemctlTimers(string(out))
	if len(items) == 0 {
		return listLocalCron(), nil
	}
	return items, nil
}

func parseSystemctlTimers(raw string) []ScheduledItem {
	var items []ScheduledItem
	scanner := bufio.NewScanner(strings.NewReader(raw))

	// Skip header line
	headerSeen := false
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "NEXT") {
			headerSeen = true
			continue
		}
		if strings.Contains(line, "timers listed") {
			break
		}
		if !headerSeen {
			continue
		}

		fields := strings.Fields(line)
		if len(fields) < 5 {
			continue
		}

		// Typical line:
		// Sat 2026-09-12 00:00:00 UTC  6h left  Fri 2026-09-11 18:00:00 UTC  10min ago  logrotate.timer  logrotate.service
		// The last two fields are the timer unit and service unit
		unit := fields[len(fields)-2]
		activates := fields[len(fields)-1]

		if !strings.HasSuffix(unit, ".timer") {
			continue
		}

		items = append(items, ScheduledItem{
			Name:     unit,
			Schedule: activates,
			LastRun:  "recent",
			NextRun:  fields[0] + " " + fields[1],
			Status:   "ok",
			Meta:     fmt.Sprintf("triggers %s", activates),
			Ok:       true,
			Actions:  []string{"Run now"},
		})
	}
	return items
}

func listLocalCron() []ScheduledItem {
	items := make([]ScheduledItem, 0)

	// Check /etc/cron.d, /etc/crontab
	files := []string{"/etc/crontab"}
	entries, _ := filepath.Glob("/etc/cron.d/*")
	files = append(files, entries...)

	for _, fpath := range files {
		f, err := os.Open(fpath)
		if err != nil {
			continue
		}
		scanner := bufio.NewScanner(f)
		for scanner.Scan() {
			line := strings.TrimSpace(scanner.Text())
			if line == "" || strings.HasPrefix(line, "#") {
				continue
			}
			parts := strings.Fields(line)
			if len(parts) >= 6 {
				sched := strings.Join(parts[:5], " ")
				cmd := strings.Join(parts[5:], " ")
				if len(cmd) > 30 {
					cmd = cmd[:30] + "..."
				}
				items = append(items, ScheduledItem{
					Name:     filepath.Base(fpath) + ": " + cmd,
					Schedule: sched,
					LastRun:  "—",
					NextRun:  "cron managed",
					Status:   "ok",
					Meta:     sched,
					Ok:       true,
					Actions:  []string{}, // Passive cron jobs cannot be started via systemctl
				})
			}
		}
		f.Close()
	}

	return items
}

// TriggerScheduled triggers immediate run of a timer unit.
func TriggerScheduled(name string) error {
	if !strings.HasSuffix(name, ".timer") {
		return fmt.Errorf("only systemd .timer units can be triggered on-demand")
	}
	if !validUnitName.MatchString(name) {
		return fmt.Errorf("invalid schedule name")
	}

	serviceName := strings.TrimSuffix(name, ".timer") + ".service"
	return ServiceAction(serviceName, "start")
}
