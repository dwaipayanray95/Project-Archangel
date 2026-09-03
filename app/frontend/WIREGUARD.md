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
| macOS | **Custom**: a bundled, officially-sourced `wireguard-go` binary driven directly (`macos/Runner/WireGuardMacOS.swift`), not wireguard_flutter's darwin backend | **Working, verified end-to-end on real hardware** — tunnel connects and a real Terminal shell session opens against the real deployed server. Five real bugs found and fixed via actual device testing along the way; see below for the full history and one remaining rough edge. |

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
socket appears and before connecting to it.

**Third round: a real Swift compile error** — `Int8`/`UInt8` type mismatch
copying the socket path into `sockaddr_un` (`withUnsafeMutableBytes`
exposes raw `UInt8` regardless of `sun_path`'s own C `char`/`Int8` element
type). Fixed by dropping the unnecessary `Int8(bitPattern:)` conversion.

**Tunnel itself connects after all of the above** — top bar shows
green/connected, real device against a real server. That turned out not
to mean actual traffic could reach the server yet, though: opening a
Terminal tab against the server's tunnel address (`10.10.0.1:8443`) just
hung on "connecting" forever rather than erroring.

**Fourth round: no route was ever configured for the peer's address.**
`bringUpInterface` only ran `ifconfig` on the interface's own address
(`10.10.0.3`) — nothing told macOS that traffic to `10.10.0.1` (the
server) should go through the tunnel at all, so it silently fell through
to the normal default route (WiFi), which has no path to a private
tunnel-only address and just hangs rather than erroring cleanly. This is
exactly the gap this file's comments had already called out as
unaddressed — it just took an actual Terminal connection attempt to
surface it as a real, live blocker rather than a theoretical one. Fixed:
`bringUpInterface` now also runs `route add -net <cidr> -interface
<ifname>` for each entry in the config's `AllowedIPs` (skipping a
full-tunnel `0.0.0.0/0`, which still needs more care to avoid breaking
the Mac's normal internet access — not archangeld's use case, which uses
a narrow AllowedIPs).

**✅ Confirmed working end-to-end**: real device, real deployed server,
real Terminal shell session opened over the tunnel this app's own
WireGuard backend manages. (One rough edge: the very first connect
attempt after this fix needed a manual reconnect before Terminal picked
up the new route — worth a look as a follow-up, see below.)

**Remaining known rough edges:**
- The first connect attempt right after a fresh app launch may need a
  manual Reconnect before Terminal traffic flows — seen once, not yet
  root-caused (candidate: a race between the route being added and the
  app's own retry/connect timing; hasn't recurred on subsequent
  reconnects within the same session).
- Full-tunnel `0.0.0.0/0` `AllowedIPs` still isn't routed (see above) —
  fine for archangeld's own narrow `AllowedIPs`, not a general-purpose
  WireGuard client yet.
- Three separate admin password prompts per connect (launch
  `wireguard-go`, relax socket permissions, configure the route) — works,
  but worth consolidating into fewer prompts as a UX pass later.

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
