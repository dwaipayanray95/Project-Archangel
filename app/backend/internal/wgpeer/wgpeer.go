// Package wgpeer manages WireGuard peers for the `archangeld pair` command:
// reading the server's own identity out of wg0.conf, picking the next free
// tunnel IP, generating a device keypair, and adding the new peer both live
// (via `wg set`, effective immediately) and persistently (appended to
// wg0.conf, so it survives a reboot/wg-quick restart). Mirrors the exact
// conventions infra/scripts/wireguard_setup.sh already established: same
// subnet layout (server = .1, peers = .2+), same `wg genkey`/`wg pubkey`
// shell-out approach (no cgo/C WireGuard bindings needed).
//
// Requires the `wireguard-tools` package (for `wg`) and, in practice, root
// (wg0.conf is 600 root:root and `wg set` changes live kernel/wireguard-go
// state) - archangeld's `pair` subcommand is meant to be run via sudo, the
// same way wireguard_setup.sh already runs.
package wgpeer

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

// GenerateKeypair shells out to `wg genkey`/`wg pubkey` - the same two
// commands wireguard_setup.sh uses - rather than reimplementing Curve25519
// key generation.
func GenerateKeypair() (privateKey, publicKey string, err error) {
	genOut, err := exec.Command("wg", "genkey").Output()
	if err != nil {
		return "", "", fmt.Errorf("wg genkey: %w", err)
	}
	privateKey = strings.TrimSpace(string(genOut))
	if privateKey == "" {
		return "", "", fmt.Errorf("wg genkey returned an empty key")
	}

	pubCmd := exec.Command("wg", "pubkey")
	pubCmd.Stdin = strings.NewReader(privateKey)
	pubOut, err := pubCmd.Output()
	if err != nil {
		return "", "", fmt.Errorf("wg pubkey: %w", err)
	}
	publicKey = strings.TrimSpace(string(pubOut))
	if publicKey == "" {
		return "", "", fmt.Errorf("wg pubkey returned an empty key")
	}

	return privateKey, publicKey, nil
}

// ServerInfo reads the server's own public key (derived from wg0.conf's
// PrivateKey) and listen port, so a pairing bundle can tell the new device
// how to reach this server.
func ServerInfo(wgDir, iface string) (publicKey string, listenPort int, err error) {
	confPath := filepath.Join(wgDir, iface+".conf")
	data, err := os.ReadFile(confPath)
	if err != nil {
		return "", 0, fmt.Errorf("reading %s: %w", confPath, err)
	}

	var privateKey string
	listenPort = 51820
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "[Peer]") {
			break // only the [Interface] block (the server itself) matters here
		}
		switch {
		case strings.HasPrefix(line, "PrivateKey"):
			privateKey = valueAfterEquals(line)
		case strings.HasPrefix(line, "ListenPort"):
			if p, err := strconv.Atoi(valueAfterEquals(line)); err == nil {
				listenPort = p
			}
		}
	}
	if privateKey == "" {
		return "", 0, fmt.Errorf("no PrivateKey found in %s", confPath)
	}

	pubCmd := exec.Command("wg", "pubkey")
	pubCmd.Stdin = strings.NewReader(privateKey)
	pubOut, err := pubCmd.Output()
	if err != nil {
		return "", 0, fmt.Errorf("wg pubkey: %w", err)
	}
	publicKey = strings.TrimSpace(string(pubOut))
	if publicKey == "" {
		return "", 0, fmt.Errorf("wg pubkey returned an empty key")
	}

	return publicKey, listenPort, nil
}

// NextFreeIP scans wg0.conf's existing AllowedIPs entries in subnet
// (e.g. "10.10.0") and returns the lowest unused host address, starting at
// .2 (.1 is always the server itself).
func NextFreeIP(wgDir, iface, subnet string) (string, error) {
	confPath := filepath.Join(wgDir, iface+".conf")
	data, err := os.ReadFile(confPath)
	if err != nil {
		return "", fmt.Errorf("reading %s: %w", confPath, err)
	}

	used := map[int]bool{1: true}
	re := regexp.MustCompile(regexp.QuoteMeta(subnet) + `\.(\d+)/32`)
	for _, m := range re.FindAllStringSubmatch(string(data), -1) {
		if n, err := strconv.Atoi(m[1]); err == nil {
			used[n] = true
		}
	}

	for n := 2; n < 255; n++ {
		if !used[n] {
			return fmt.Sprintf("%s.%d", subnet, n), nil
		}
	}
	return "", fmt.Errorf("no free addresses left in %s.0/24", subnet)
}

// AddPeer adds a new peer both live (so it works immediately, no tunnel
// restart) and persistently (appended to wg0.conf, so it survives one).
func AddPeer(wgDir, iface, name, publicKey, ip string) error {
	allowedIP := ip + "/32"

	setCmd := exec.Command("wg", "set", iface, "peer", publicKey, "allowed-ips", allowedIP)
	if out, err := setCmd.CombinedOutput(); err != nil {
		return fmt.Errorf("wg set (live peer add): %w: %s", err, strings.TrimSpace(string(out)))
	}

	confPath := filepath.Join(wgDir, iface+".conf")
	f, err := os.OpenFile(confPath, os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return fmt.Errorf("opening %s to persist new peer: %w", confPath, err)
	}
	defer f.Close()

	block := fmt.Sprintf("\n[Peer]\n# %s\nPublicKey = %s\nAllowedIPs = %s\n", name, publicKey, allowedIP)
	if _, err := f.WriteString(block); err != nil {
		return fmt.Errorf("writing new peer block to %s: %w", confPath, err)
	}
	return nil
}

func valueAfterEquals(line string) string {
	parts := strings.SplitN(line, "=", 2)
	if len(parts) != 2 {
		return ""
	}
	return strings.TrimSpace(parts[1])
}
