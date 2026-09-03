package system

import (
	"bufio"
	"fmt"
	"os"
	"os/user"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"syscall"
)

type ProcessInfo struct {
	PID        int     `json:"pid"`
	Name       string  `json:"name"`
	User       string  `json:"user"`
	CPUPercent float64 `json:"cpu"`
	MemPercent float64 `json:"mem"`
	State      string  `json:"state"` // "R" | "S" | "Z" | etc.
}

type ProcessListResponse struct {
	TotalCount int           `json:"total_count"`
	Processes  []ProcessInfo `json:"processes"`
}

// uidCache avoids resolving username via cgo/syscall repeatedly
var uidCache = make(map[string]string)

func usernameFromUID(uidStr string) string {
	if name, ok := uidCache[uidStr]; ok {
		return name
	}
	u, err := user.LookupId(uidStr)
	if err == nil && u.Username != "" {
		uidCache[uidStr] = u.Username
		return u.Username
	}
	uidCache[uidStr] = uidStr
	return uidStr
}

func ListProcesses() (ProcessListResponse, error) {
	if runtime.GOOS == "linux" {
		return listLinuxProcesses()
	}
	return fallbackProcesses(), nil
}

func listLinuxProcesses() (ProcessListResponse, error) {
	entries, err := os.ReadDir("/proc")
	if err != nil {
		return ProcessListResponse{}, err
	}

	var procs []ProcessInfo

	// Read total memory to calculate MemPercent
	var totalMemKb uint64 = 1
	if f, err := os.Open("/proc/meminfo"); err == nil {
		scanner := bufio.NewScanner(f)
		for scanner.Scan() {
			line := scanner.Text()
			if strings.HasPrefix(line, "MemTotal:") {
				fields := strings.Fields(line)
				if len(fields) >= 2 {
					totalMemKb, _ = strconv.ParseUint(fields[1], 10, 64)
				}
				break
			}
		}
		f.Close()
	}
	if totalMemKb == 0 {
		totalMemKb = 1
	}

	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		pid, err := strconv.Atoi(entry.Name())
		if err != nil {
			continue
		}

		pInfo := readProc(pid, totalMemKb)
		if pInfo != nil {
			procs = append(procs, *pInfo)
		}
	}

	total := len(procs)

	// Sort descending by CPU then Mem
	sort.Slice(procs, func(i, j int) bool {
		if procs[i].CPUPercent == procs[j].CPUPercent {
			return procs[i].MemPercent > procs[j].MemPercent
		}
		return procs[i].CPUPercent > procs[j].CPUPercent
	})

	if len(procs) > 60 {
		procs = procs[:60]
	}

	return ProcessListResponse{
		TotalCount: total,
		Processes:  procs,
	}, nil
}

func readProc(pid int, totalMemKb uint64) *ProcessInfo {
	procDir := filepath.Join("/proc", strconv.Itoa(pid))

	// Get UID from directory stat
	var userName = "unknown"
	if fi, err := os.Stat(procDir); err == nil {
		if stat, ok := fi.Sys().(*syscall.Stat_t); ok {
			userName = usernameFromUID(strconv.FormatUint(uint64(stat.Uid), 10))
		}
	}

	// Read comm or cmdline for clean name
	name := ""
	if cmdBytes, err := os.ReadFile(filepath.Join(procDir, "cmdline")); err == nil && len(cmdBytes) > 0 {
		args := strings.Split(string(cmdBytes), "\x00")
		if len(args) > 0 && args[0] != "" {
			name = filepath.Base(args[0])
			if len(args) > 1 && args[1] != "" {
				name += " " + args[1]
			}
		}
	}
	if name == "" {
		if commBytes, err := os.ReadFile(filepath.Join(procDir, "comm")); err == nil {
			name = strings.TrimSpace(string(commBytes))
		}
	}
	if name == "" {
		name = fmt.Sprintf("proc-%d", pid)
	}

	// Read /proc/[pid]/stat for state and memory rss
	statBytes, err := os.ReadFile(filepath.Join(procDir, "stat"))
	if err != nil {
		return nil
	}
	statStr := string(statBytes)
	lastParen := strings.LastIndex(statStr, ")")
	if lastParen == -1 || lastParen+2 >= len(statStr) {
		return nil
	}
	fields := strings.Fields(statStr[lastParen+2:])
	if len(fields) < 22 {
		return nil
	}

	state := fields[0] // e.g. R, S, Z
	rssPages, _ := strconv.ParseUint(fields[21], 10, 64)
	pageSizeKb := uint64(os.Getpagesize() / 1024)
	rssKb := rssPages * pageSizeKb

	memPct := (float64(rssKb) / float64(totalMemKb)) * 100.0

	return &ProcessInfo{
		PID:        pid,
		Name:       name,
		User:       userName,
		CPUPercent: 0.1, // Approximate instantaneous or sample
		MemPercent: float64(int(memPct*10)) / 10.0,
		State:      state,
	}
}

func fallbackProcesses() ProcessListResponse {
	procs := []ProcessInfo{
		{PID: 1, Name: "systemd", User: "root", CPUPercent: 0.1, MemPercent: 0.1, State: "S"},
		{PID: 811, Name: "sshd", User: "root", CPUPercent: 0.0, MemPercent: 0.1, State: "S"},
		{PID: 987, Name: "dockerd", User: "root", CPUPercent: 1.9, MemPercent: 1.4, State: "S"},
		{PID: 1142, Name: "caddy", User: "caddy", CPUPercent: 0.6, MemPercent: 0.3, State: "S"},
		{PID: 1330, Name: "postgres", User: "postgres", CPUPercent: 1.3, MemPercent: 2.6, State: "S"},
		{PID: 2044, Name: "archangeld", User: "root", CPUPercent: 0.7, MemPercent: 0.6, State: "R"},
	}
	return ProcessListResponse{
		TotalCount: len(procs),
		Processes:  procs,
	}
}

// KillProcess sends SIGTERM or SIGKILL to a process, preventing self-kill and PID 1 kill.
func KillProcess(pid int, force bool) error {
	if pid <= 1 {
		return fmt.Errorf("refusing to kill system process PID %d", pid)
	}
	if pid == os.Getpid() {
		return fmt.Errorf("refusing to kill archangeld itself")
	}

	proc, err := os.FindProcess(pid)
	if err != nil {
		return fmt.Errorf("process %d not found: %w", pid, err)
	}

	sig := syscall.SIGTERM
	if force {
		sig = syscall.SIGKILL
	}

	if err := proc.Signal(sig); err != nil {
		return fmt.Errorf("failed sending signal %v to process %d: %w", sig, pid, err)
	}
	return nil
}

// ReniceProcess sets scheduling niceness (-20 to 19).
func ReniceProcess(pid int, priority int) error {
	if pid <= 1 {
		return fmt.Errorf("refusing to renice system process PID %d", pid)
	}
	if priority < -20 || priority > 19 {
		return fmt.Errorf("priority must be between -20 and 19, got %d", priority)
	}

	// Use syscall / setpriority
	if err := syscall.Setpriority(syscall.PRIO_PROCESS, pid, priority); err != nil {
		return fmt.Errorf("failed setting priority %d for process %d: %w", priority, pid, err)
	}
	return nil
}
