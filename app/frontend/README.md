# Archangel (Flutter app)

The Flutter app (Android/Windows/macOS/Linux from one codebase) that's the
GUI for [`archangeld`](../backend/README.md), a Go backend running on a
personal VPS, reachable only over a WireGuard tunnel this app itself
manages (it *is* the VPN client, not a wrapper around one). The app also
sets the server up in the first place - see below.

For the detailed working-notes handoff (what's verified vs. not, file
map, known gaps) see **[`WORKING.md`](WORKING.md)**. Per-platform
WireGuard implementation details: **[`WIREGUARD.md`](WIREGUARD.md)**.

## What the app does

- **First run**: if nothing is paired yet, choose between "Set up a new
  server" (the in-app SSH wizard - `lib/screens/setup/setup_wizard_screen.dart`,
  `lib/services/vps_setup_service.dart`) and "I already have a pairing
  code" (the manual pairing dialog). The wizard bootstraps a fresh
  Ubuntu/Debian VPS end-to-end: baseline setup, WireGuard, downloads the
  matching `archangeld` release binary, installs the systemd service,
  and auto-pairs - no manual SSH required. Safe to re-run against an
  already-set-up server.
- **Terminal**: a real PTY shell over WebSocket (`lib/services/terminal_session.dart`).
- **Monitoring**: live CPU/memory/disk metrics and process list
  (kill/renice) from the real backend, falling back to mock data if
  unpaired or unreachable (`lib/services/monitoring_service.dart`).
- **Files**: a jailed file browser (list/preview/download) scoped to
  whatever the server's `files_root` actually is - the sidebar shows the
  real root and its real subdirectories, never a guessed system path
  (`lib/services/files_service.dart`).
- **Settings**: shows the project/app/backend version (from the shared
  root [`VERSION`](../../VERSION) file and the backend's live
  `/api/v1/health`), checks GitHub for newer releases, and - when the
  backend is behind - lets you update it in place over SSH with
  automatic rollback if the new version doesn't come up healthy
  (`lib/services/update_check_service.dart`,
  `lib/widgets/backend_update_dialog.dart`). See
  [`app/backend/README.md`](../backend/README.md#releases) for why this
  goes over SSH rather than a self-update endpoint.
- **Containers / DevOps**: still 100% mock data (`lib/data/mock_data.dart`)
  - no backend routes exist for these yet.

## Development

```bash
flutter pub get
flutter run -d linux   # or macos/windows/an emulator - see flutter devices
```

`flutter analyze` and `flutter test` should stay clean; `dart format .`
before committing. `scripts/sync_version.sh` syncs `pubspec.yaml`'s
version and `lib/services/app_version.dart`'s constants from the root
`VERSION` file - run it after bumping `VERSION` (CI also runs it before
every release build).

## Releases

Frontend builds (macOS `.app`, Windows, Android arm64-v8a APK) are
published by the same tag-triggered pipeline as the backend - see
[`app/backend/README.md#releases`](../backend/README.md#releases) for
the full tag-suffix scheme and freeze-logic details. `pubspec.yaml`'s
`version:` field is kept in sync with `VERSION`'s `FRONTEND` line by
`sync_version.sh`, run automatically in CI before each build.
