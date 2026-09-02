# WireGuard integration status

Archangel talks to `archangeld` only over a WireGuard tunnel (`archangeld`
binds to the tunnel interface, never the public IP — see `app/backend/README.md`).
The app manages that tunnel itself via [`wireguard_flutter`](https://pub.dev/packages/wireguard_flutter),
which wraps the real WireGuard implementations per platform rather than a
hand-rolled one.

## Where things stand, per platform

| Platform | Backend | Status |
|---|---|---|
| Android | `VpnService` (`com.wireguard.android:tunnel`) | Should work out of the box — real, maintained implementation, no manual setup beyond the `INTERNET` permission (already added). **Not yet run on a real device from this session.** |
| Windows | Bundled `WireGuardNT` (`tunnel.dll`/`wireguard.dll`) run as a Windows service | Should work — the app now requests admin elevation on launch (`windows/runner/runner.exe.manifest`) since creating the service needs it. **Not yet run on real Windows.** |
| Linux | Shells out to `wg`/`wg-quick` via `sudo` | Verified end-to-end in this session (see below) — needs `wireguard-tools` installed and either passwordless sudo or an interactive terminal for the sudo prompt. |
| macOS | Apple `NetworkExtension` / `NETunnelProviderManager` | **Not wired up yet — needs a manual Xcode step, see below.** |

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

## macOS: manual step required

`wireguard_flutter`'s macOS backend uses Apple's real VPN framework, which
requires a **Packet Tunnel Provider app extension** as a separate target in
the Xcode project — this can't be done by editing text files blindly, it's
Xcode project surgery plus signing setup:

1. Open `macos/Runner.xcworkspace` in Xcode.
2. File → New → Target → **Network Extension** (Packet Tunnel Provider).
   Name it something like `ArchangelTunnel`.
3. Give both the main app target and the new extension target the
   **Network Extensions** capability (Signing & Capabilities), and add
   them to the same **App Group**.
4. This requires an active **Apple Developer Program** membership — the
   Network Extension entitlement isn't available on a free account.
5. Update `_kProviderBundleId` in
   `lib/services/wireguard_controller.dart` to match the extension's
   actual bundle identifier once it exists.

Until that target exists, `bootstrap()` on macOS will surface a clear
error in the Tunnel card (same graceful-degradation path verified on
Linux above) rather than crash — but tunnels won't connect on macOS until
this is done.

## Pairing flow (all platforms)

Settings → Tunnel → **Pair device**, paste the wg-quick config (the
`[Interface]`/`[Peer]` block `archangeld`'s pairing flow will eventually
generate — that generation doesn't exist on the backend yet either, only
milestone 1 is built). The parsed config's private key is stored via
`flutter_secure_storage` (OS keychain/keystore/credential manager per
platform), never in plaintext.
