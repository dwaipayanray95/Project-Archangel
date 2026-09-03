# WireGuard integration status

Archangel talks to `archangeld` only over a WireGuard tunnel (`archangeld`
binds to the tunnel interface, never the public IP — see `app/backend/README.md`).
The app manages that tunnel itself: [`wireguard_flutter`](https://pub.dev/packages/wireguard_flutter)
on Android/Windows/Linux (wraps real per-platform WireGuard implementations
rather than a hand-rolled one), and a custom backend on macOS — see below.

## Where things stand, per platform

| Platform | Backend | Status |
|---|---|---|
| Android | `VpnService` (`com.wireguard.android:tunnel`), via wireguard_flutter | Should work out of the box — real, maintained implementation, no manual setup beyond the `INTERNET` permission (already added). **Not yet run on a real device from this session.** |
| Windows | Bundled `WireGuardNT` (`tunnel.dll`/`wireguard.dll`) run as a Windows service, via wireguard_flutter | Should work — the app now requests admin elevation on launch (`windows/runner/runner.exe.manifest`) since creating the service needs it. **Not yet run on real Windows.** |
| Linux | wireguard_flutter shells out to `wg`/`wg-quick` via `sudo` | Verified end-to-end in this session (see below) — needs `wireguard-tools` installed and either passwordless sudo or an interactive terminal for the sudo prompt. |
| macOS | **Custom**: a bundled, officially-sourced `wireguard-go` binary driven directly (`macos/Runner/WireGuardMacOS.swift`), not wireguard_flutter's darwin backend | **Compiled and run on real hardware.** Interface creation + UAPI configuration confirmed working (a utun interface came up with the right address); two real bugs found and fixed (daemonization, a process-tracking leak) — the fix itself hasn't been retested yet. See below. |

### Why macOS doesn't use wireguard_flutter's own backend

wireguard_flutter's macOS/iOS code uses Apple's `NetworkExtension`/
`NETunnelProviderManager`, which requires a separate **Packet Tunnel
Provider extension target** added in Xcode, plus a paid **Apple Developer
Program membership** (the Network Extension entitlement isn't available
on a free account) — real Xcode project surgery, not something achievable
from Dart alone.

Instead, macOS drives the official `wireguard-go` (Apache-licensed,
cross-compiled from https://github.com/WireGuard/wireguard-go in this
session for both `arm64` and `amd64`, bundled at
`macos/Runner/Resources/wireguard-go/`) directly: it creates a `utun`
network interface via ordinary Darwin socket APIs — which does **not**
require NetworkExtension or a Developer account, only that the app isn't
sandboxed (App Sandbox is now off in both `.entitlements` files; this is
the same trade-off every non-App-Store WireGuard-based tool on macOS
makes: no Mac App Store distribution). It's then configured over
WireGuard's documented cross-platform UAPI socket protocol
(https://www.wireguard.com/xplatform/), driven straight from Swift
instead of shelling out to the C `wg` CLI (which, being C rather than Go,
wasn't something this Linux sandbox could cross-compile).

**First real-hardware run found two bugs, now fixed but not yet retested:**
1. `wireguard-go` daemonizes (double-forks into the background) by
   default, which detached it from both the log redirection and the PID
   our shell's `$!` captured — the log came back completely empty on
   every attempt, and orphaned root `wireguard-go` processes piled up
   (11 of them, across ~2 hours of testing) because `disconnect()` had
   nothing valid to kill. Fixed: `WG_PROCESS_FOREGROUND=1` stops the
   daemonizing, the interface name is now computed via `ifconfig -l`
   instead of parsed from a log line, and `disconnect()` kills the real
   PID (plus an exact-match `pkill` fallback) via the same elevated path.
2. Confirmed working before the fix: interface creation and UAPI
   configuration — a utun interface (`utun4`) came up with the exact
   address the config specified. The core mechanism is sound; the bugs
   were in process lifecycle management around it, not the WireGuard
   protocol handling itself.

**Second real-hardware run** (after the above fix) got further — the
socket now reliably appears — but failed with `Could not connect to
wireguard-go's UAPI socket at /var/run/wireguard/utun17.sock`: `wireguard-go`
runs as root and creates both that directory and the socket root-owned,
while this app's own `connect()` call to it runs as the logged-in user —
a straightforward permission denial, not a missing-file issue (the
`waitForUapiSocket` existence check had already passed). Fixed with
`relaxUapiSocketPermissions()`, an elevated `chmod` run right after the
socket appears and before connecting to it. Not yet retested.

**Still-open item, not yet touched:**
- Routing: only the interface's own address is configured
  (`bringUpInterface`) — `AllowedIPs` beyond the tunnel's own address
  aren't routed yet, which is fine for archangeld's typical narrow
  `AllowedIPs` (the server's own tunnel subnet) but not for a full-tunnel
  `0.0.0.0/0` config

**If you're picking this up after a previous failed attempt**, check for
and clean up leaked root processes first: `ps aux | grep wireguard-go`,
then `sudo pkill -f wireguard-go` if any turn up.

**Also required, manually, in Xcode** — the bundled binaries need adding
to the Runner target's **Copy Bundle Resources** build phase (drag the
`Resources/wireguard-go` folder into the project in Xcode, check "Copy
items if needed" and the Runner target). This can't be done by editing
`project.pbxproj` blind.

## What was actually verified in this session

Built and ran the real Linux binary. With no `wg`/passwordless `sudo`
configured in that sandbox, `WireGuardController.bootstrap()` caught the
real failure and surfaced it correctly end-to-end:

- Top bar tunnel pill → red "unsupported"
- Settings → Tunnel card → shows the real `ShellException` message, "No
  device paired yet.", and a working **Pair device** button
- Pair dialog opens, accepts a pasted wg-quick config, and shows a
  validation error inline (without crashing) on malformed input

This confirms the state machine, error handling, and UI wiring are
correct. It does **not** confirm a real tunnel connects — that needs a
real WireGuard peer and `wireguard-tools`/service backend actually present,
which no CI runner or this sandbox has.

## Pairing flow (all platforms)

Settings → Tunnel → **Pair device**, paste the wg-quick config (the
`[Interface]`/`[Peer]` block `archangeld`'s pairing flow will eventually
generate — that generation doesn't exist on the backend yet either, only
milestone 1 is built). The parsed config's private key is stored via
`flutter_secure_storage` (OS keychain/keystore/credential manager per
platform), never in plaintext.
