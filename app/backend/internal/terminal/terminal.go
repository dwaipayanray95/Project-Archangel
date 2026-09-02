// Package terminal bridges a real PTY (pseudo-terminal) shell to a
// WebSocket connection, so the Flutter app gets a genuine interactive
// terminal - not just "run a command, get output back". Interactive
// programs (nano, htop, a shell prompt asking y/n) work correctly because
// this is a real PTY, the same mechanism a normal SSH session uses.
package terminal

import (
	"encoding/base64"
	"encoding/json"
	"log/slog"
	"net/http"
	"os"
	"os/exec"
	"sync"
	"sync/atomic"
	"time"

	"github.com/creack/pty"
	"github.com/gorilla/websocket"

	"github.com/dwaipayanray95/project-archangel/backend/internal/wsproto"
)

// MaxSessions caps concurrent terminal sessions. This is a single-user
// tool; a handful of tabs is plenty, and capping this bounds worst-case
// memory/process usage on a 1GB box.
const MaxSessions = 3

var activeSessions atomic.Int32

var upgrader = websocket.Upgrader{
	// Single-user personal tool behind WireGuard - the origin check that
	// matters (network reachability) is already enforced by the bind
	// address and firewall, not by browser Origin headers.
	CheckOrigin: func(r *http.Request) bool { return true },
}

func Handler(w http.ResponseWriter, r *http.Request) {
	if activeSessions.Load() >= MaxSessions {
		http.Error(w, "too many concurrent terminal sessions", http.StatusServiceUnavailable)
		return
	}

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		slog.Error("terminal: websocket upgrade failed", "err", err)
		return
	}
	defer conn.Close()

	activeSessions.Add(1)
	defer activeSessions.Add(-1)

	shell := os.Getenv("SHELL")
	if shell == "" {
		shell = "/bin/bash"
	}
	cmd := exec.Command(shell, "-l")

	ptmx, err := pty.Start(cmd)
	if err != nil {
		slog.Error("terminal: failed to start pty", "err", err)
		sendFrame(conn, wsproto.Frame{Type: wsproto.TypeError, Message: "failed to start shell"})
		return
	}
	defer ptmx.Close()

	// Default size; the client sends a "resize" frame right after connecting
	// with its real terminal dimensions.
	_ = pty.Setsize(ptmx, &pty.Winsize{Rows: 24, Cols: 80})

	var writeMu sync.Mutex
	safeSendFrame := func(f wsproto.Frame) error {
		writeMu.Lock()
		defer writeMu.Unlock()
		return conn.WriteJSON(f)
	}

	// PTY output -> WebSocket. When the shell itself exits (not just the
	// client disconnecting), ptmx.Read returns EOF here - but that alone
	// doesn't wake the WebSocket read loop below, which is blocked waiting
	// for client input that may never come. Forcing an immediate read
	// deadline makes conn.ReadMessage() return an error (without killing
	// the socket outright) so the main loop reaches the cleanup path and
	// still gets to send the "exit" frame the client is waiting for -
	// closing the connection directly here would race with that send.
	done := make(chan struct{})
	go func() {
		defer close(done)
		buf := make([]byte, 4096)
		for {
			n, err := ptmx.Read(buf)
			if n > 0 {
				frame := wsproto.Frame{
					Type: wsproto.TypeStdout,
					Data: base64.StdEncoding.EncodeToString(buf[:n]),
				}
				if werr := safeSendFrame(frame); werr != nil {
					return
				}
			}
			if err != nil {
				_ = conn.SetReadDeadline(time.Now())
				return
			}
		}
	}()

	// WebSocket input -> PTY
	for {
		_, raw, err := conn.ReadMessage()
		if err != nil {
			break
		}

		var frame wsproto.Frame
		if err := json.Unmarshal(raw, &frame); err != nil {
			continue
		}

		switch frame.Type {
		case wsproto.TypeStdin:
			data, err := base64.StdEncoding.DecodeString(frame.Data)
			if err != nil {
				continue
			}
			if _, err := ptmx.Write(data); err != nil {
				goto cleanup
			}
		case wsproto.TypeResize:
			if frame.Cols > 0 && frame.Rows > 0 {
				_ = pty.Setsize(ptmx, &pty.Winsize{
					Rows: uint16(frame.Rows),
					Cols: uint16(frame.Cols),
				})
			}
		case wsproto.TypePing:
			_ = safeSendFrame(wsproto.Frame{Type: wsproto.TypePong})
		}
	}

cleanup:
	// Kill covers the client-disconnect case (shell may still be running);
	// it's a no-op error (ignored) if the shell already exited on its own.
	// Wait is required either way - without it cmd.ProcessState is never
	// populated (exit code would always read as 0) and the child process
	// is never reaped, leaking a zombie process per terminal session.
	_ = cmd.Process.Kill()
	_ = cmd.Wait()
	<-done

	exitCode := 0
	if state := cmd.ProcessState; state != nil {
		exitCode = state.ExitCode()
	}
	_ = safeSendFrame(wsproto.Frame{Type: wsproto.TypeExit, Code: exitCode})
}

func sendFrame(conn *websocket.Conn, f wsproto.Frame) {
	_ = conn.WriteJSON(f)
}
