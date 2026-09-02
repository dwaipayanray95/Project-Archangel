# Archangel frontend — working notes / handoff

Status snapshot for picking this up cold. Read this before touching
anything — it'll save you from re-discovering things the hard way.

## What this is

A Flutter app (Android/Windows/macOS/Linux from one codebase) that's the
GUI for `archangeld`, a Go backend running on a personal VPS, reachable
only over a WireGuard tunnel. Design source: a Claude Design mockup
(`Archangel.dc.html`, dark cockpit aesthetic) — the design brief and
mockup markup aren't in this repo, only the Flutter implementation of it.

Sibling doc: **`WIREGUARD.md`** in this same folder — read that too, it
has the full per-platform WireGuard status and is more detailed than the
summary below.

## What actually works, verified for real (not just "should work")

- **App shell**: top status bar, sidebar nav (bottom tabs on phone width),
  ⌘K command palette — all 7 sections (Overview, Monitoring, Files,
  Containers, DevOps, Terminal, Settings) render correctly. Verified by
  building and running the real Linux binary in a sandbox and screenshotting
  every section.
- **Terminal ↔ archangeld, end-to-end, for real**: built and ran the actual
  `archangeld` Go binary locally, then drove the exact JSON frame protocol
  `TerminalSession` implements against it — a real PTY executed `whoami`
  and `uname -a` and returned real output over the real WebSocket. This is
  the strongest verification anything in this repo has.
- **WireGuard state machine on Linux**: real `wireguard_flutter` package,
  real failure path exercised (no `wg`/sudo in that sandbox → surfaced
  correctly as "unsupported" in both the top bar and Settings, no crash).
- `flutter analyze`: clean. `flutter test test/widget_test.dart`: passes.

## What's built but NOT verified (no toolchain existed to test it)

The sandbox this was built in is Linux-only — no Android SDK, no Xcode,
no Windows toolchain. Everything below is real, complete code, but
**unverified**:

- **Android**: wiring is correct (`wireguard_flutter`'s real `VpnService`
  backend, `INTERNET` permission added), never run on a device or emulator.
- **Windows**: same — `wireguard_flutter` bundles real `WireGuardNT`
  binaries, app now requests admin elevation on launch (needed to create
  the tunnel service). Never compiled with an actual Windows toolchain.
- **macOS WireGuard — the biggest unverified piece.** `wireguard_flutter`'s
  macOS backend needs Apple's NetworkExtension framework, which needs a
  separate Xcode target + paid Apple Developer Program membership. Instead,
  built a **custom backend**: cross-compiled the real, official
  `wireguard-go` (Apache-licensed, from `github.com/WireGuard/wireguard-go`)
  for both `arm64`/`amd64`, bundled it, and wrote a Swift plugin
  (`macos/Runner/WireGuardMacOS.swift`) that drives it directly via
  WireGuard's documented UAPI socket protocol, elevated via a native admin-
  password prompt. **This Swift code has never been compiled.** See
  `WIREGUARD.md`'s "Why macOS doesn't use wireguard_flutter's own backend"
  section for the exact spots most likely to need a fix (the interface-name
  log-line regex, the elevated-process handling).
- **CI workflow** (`.github/workflows/build-app.yml`): manual
  `workflow_dispatch` with checkboxes for macOS/Windows/Android/backend/all.
  Caches Flutter pub packages and Gradle. Had a real path bug in the
  Windows zip step (fixed in commit `517cbd6` — verify it actually works
  by running the workflow, since it was never actually executed against
  GitHub Actions, only checked by re-deriving the path math by hand).

## Known gaps / things to do next, roughly in priority order

1. **Run the CI workflow for real** at least once per target
   (macOS/Windows/Android/backend) and fix whatever breaks — none of it
   has actually executed on GitHub's runners yet, only been reasoned
   through.
2. **macOS WireGuard**: needs the one manual Xcode step first — add
   `macos/Runner/Resources/wireguard-go/` to the Runner target's Copy
   Bundle Resources (drag into Xcode, "Copy items if needed"). Then
   `flutter run -d macos` and debug from real compiler/runtime errors.
3. **Android/Windows real-device testing**: nobody has run this app on
   either platform yet. Expect friction — this is genuinely the first
   time this code has met a real toolchain for either.
4. **archangeld has no pairing endpoint** — the app's "Pair backend" and
   "Pair device" (WireGuard) dialogs require pasting host/token or a
   wg-quick config by hand, because the backend has no `/api/v1/pair`-type
   route yet (only Milestone 1: health + terminal are built server-side —
   see `app/backend/README.md`). Files/Containers/Monitoring/DevOps
   screens are still 100% mock data (`lib/data/mock_data.dart`) for the
   same reason: no backend routes exist for them yet.
5. **Terminal is not a full terminal emulator** — `TerminalSession`
   renders raw output, no ANSI/VT100 escape sequence handling. Fine for
   plain shell use, will show garbage for `htop`/`vim`/colored output.
   The `xterm` Flutter package is the natural next layer if that's wanted.
6. **macOS WireGuard routing is incomplete** — only the tunnel interface's
   own address gets configured (`ifconfig`); `AllowedIPs` beyond that
   aren't routed. Fine for archangeld's typical narrow AllowedIPs, not for
   a full-tunnel `0.0.0.0/0` config. See `WireGuardMacOS.swift`'s
   `bringUpInterface`.

## File map (where things live)

```
lib/
  main.dart                    — app entry, provider wiring
  theme/                       — design tokens ported from the mockup's CSS
  data/
    app_state.dart             — section/accent-color app state
    mock_data.dart             — all the fake data most screens still use
  services/
    tunnel_config.dart         — wg-quick config parse/render
    wireguard_controller.dart  — WireGuard state machine, routes to per-platform backend
    macos_wireguard_channel.dart — Dart side of the macOS MethodChannel
    archangeld_connection.dart — backend host/token pairing + storage
    terminal_session.dart      — the real PTY-over-WebSocket client
  widgets/                     — shell chrome (top bar, sidebar, command palette)
  screens/                     — the 7 sections

macos/Runner/
  WireGuardMacOS.swift         — the unverified native WireGuard backend
  Resources/wireguard-go/      — cross-compiled real wireguard-go binaries
  DebugProfile.entitlements, Release.entitlements — App Sandbox OFF (required)

windows/runner/
  runner.exe.manifest          — requests admin elevation (needed for the tunnel service)

.github/workflows/build-app.yml — manual multi-target CI build

WIREGUARD.md                   — detailed per-platform WireGuard status (read this)
```

## How to pick this up

Read `WIREGUARD.md` in full, then start at gap #1 or #2 above depending on
what you have available (a Mac gets you further than CI access alone).
Everything in this repo is on `main` — there's no feature branch to find.
