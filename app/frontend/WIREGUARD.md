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
| macOS | **Custom**: a bundled, officially-sourced `wireguard-go` binary driven directly (`macos/Runner/WireGuardMacOS.swift`), not wireguard_flutter's darwin backend | Real implementation, cross-compiled and bundled in this session — **not yet compiled or run**, no macOS toolchain in this sandbox. See below. |

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

**This Swift code has never been compiled** — there is no macOS toolchain
available in the environment it was written in. The most likely spots to
need a fix during the first real build/run:
- The exact log line `wireguard-go` prints for its assigned interface
  name (`waitForInterfaceName` parses this with a regex that's a
  best-effort match against known behavior, not something confirmed
  against a real run)
- The elevated-process (`osascript ... with administrator privileges`)
  plumbing for launching `wireguard-go` in the background and later
  finding/terminating it
- Routing: only the interface's own address is configured
  (`bringUpInterface`) — `AllowedIPs` beyond the tunnel's own address
  aren't routed yet, which is fine for archangeld's typical narrow
  `AllowedIPs` (the server's own tunnel subnet) but not for a full-tunnel
  `0.0.0.0/0` config

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
