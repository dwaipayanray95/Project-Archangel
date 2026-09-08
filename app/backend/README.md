# Archangel Backend

The Go control-plane server: a single static binary (`archangeld`) exposing
terminal, system-monitoring, and file-browser controls to the Flutter app —
reachable only over a WireGuard tunnel, never the public internet.

## Status

Implemented and deployed:
- `/api/v1/health` — unauthenticated liveness check, also returns the
  running binary's version (see [Versioning](#versioning) below)
- `/ws/terminal` — real interactive PTY shell over WebSocket, token-authed
- `/api/v1/system/metrics`, `/api/v1/system/processes`
  (+ `/{pid}/kill`, `/{pid}/renice`), `/ws/stats` — CPU/memory/disk
  metrics and process list/control, real `/proc` data
- `/api/v1/files/{list,read,download}` — a file browser jailed to a
  configured `files_root`, both textually and through symlinks (a
  symlink inside the root pointing outside it is treated as broken, not
  followed) — see `internal/files/service.go`'s `resolvePath`. Fails
  closed: an unset `files_root` rejects every request rather than
  defaulting to the whole filesystem
- Per-device token auth (`X-Archangel-Token` header or `?token=` query
  param for the WS handshake) plus a legacy single shared-token fallback
- `archangeld pair <device-name> [--qr] [--raw]` — one-command pairing:
  generates a WireGuard keypair, live-adds it as a peer, generates a
  per-device token, and prints one bundle (or QR code, or bare bundle
  line with `--raw` for the in-app setup wizard) the app parses to
  configure both the tunnel and the connection in one step
- `archangeld version` — prints the running build's version (see below)

Not yet implemented: Docker/container control, OCI instance control,
DevOps automation — the Containers/DevOps screens in the frontend are
still 100% mock data with no backend routes behind them.

## Versioning

The backend's version comes from the root [`VERSION`](../../VERSION)
file's `BACKEND` line, baked in at build time via `-ldflags` (see
`Makefile`'s `build-linux-amd64`/`build-linux-arm64` targets and
`internal/version`). It is:
- printed by `archangeld version` / `archangeld -v` / `archangeld --version`
- returned by `/api/v1/health`'s `version` field (unauthenticated - this
  is how the Flutter app shows "Backend version" in Settings and detects
  when a redeploy is needed)

The root `VERSION` file also carries `FRONTEND` and `ARCHANGEL`
(project-wide) version lines, each versioned and released
independently - see [Releases](#releases).

## Local development

```bash
cp config.example.yaml config.yaml
go run ./cmd/archangeld gen-token   # prints a token + the token_hash line to paste into config.yaml
make run
```

`bind_addr` in `config.yaml` should stay `127.0.0.1` for local dev — it only
becomes the WireGuard interface IP once actually deployed to the server.
`files_root` must be set to something for the file-browser routes to work
at all (see `config.example.yaml`'s comment on it).

## Pairing a new device

Once WireGuard is set up (`infra/scripts/wireguard_setup.sh`) and
`public_endpoint` is set in `config.yaml`, pair a new device in one step:

```bash
sudo /opt/archangel/archangeld pair my-phone --qr   # --qr only useful on Android
```

This picks the next free tunnel address, generates a fresh WireGuard
keypair, adds it as a live peer (persisted to `wg0.conf` too, so it
survives a reboot), generates a fresh per-device archangeld token, and
prints one base64 bundle (and, with `--qr`, the same bundle as an ASCII QR
code) containing everything the app needs — WireGuard config and
archangeld host/token together. Paste it (or scan it, Android only) into
Archangel's pairing screen. Nothing in the bundle is stored in plaintext
on the server after this — same discipline as `gen-token`. `--raw` prints
only the bare bundle line (no human-readable preamble) - what the in-app
setup wizard parses.

## Deploying to a server

**Three ways to get a binary onto a server, in order of how "hands-off" they are:**

1. **In-app setup wizard** (new servers, or updating an existing one) —
   from the Flutter app itself: "Set up a new server" on first launch
   bootstraps a fresh Ubuntu/Debian VPS entirely over SSH (baseline,
   WireGuard, binary, systemd service, pairing - no manual steps). Once
   a server is already set up, Settings' "Backend version" row shows an
   "update available" badge when a newer release exists; tapping it
   re-SSHes in (reusing a remembered key, or asking for one) to back up
   the current binary, download and version-verify the new one, restart
   the service, and auto-rollback if it doesn't come up healthy within
   ~20s. See `app/frontend/lib/services/vps_setup_service.dart`
   (`run()` for first-time setup, `updateBackend()` for updates) - this
   is deliberately SSH-based rather than a self-update HTTP endpoint,
   because `archangeld` runs as an **unprivileged** systemd user
   (`NoNewPrivileges=true`, `ProtectSystem=strict` in `archangel.service`)
   specifically so a compromised/leaked app token can't rewrite the
   binary it's running - it truly cannot update itself.
2. **`deploy.sh`** — the original scripted manual path, run from your own
   machine (Mac, etc.), not the server itself:
   ```bash
   ./deploy.sh
   # or override defaults:
   SERVER_HOST=1.2.3.4 SERVER_USER=ubuntu SSH_KEY=~/path/to/key ./deploy.sh
   ```
   Builds the binary locally, creates the `archangel` system user +
   directories on the server if they don't exist yet, copies and
   installs the binary, generates a fresh auth token **only if
   `/etc/archangel/config.yaml` doesn't already exist**, installs/updates
   the systemd service, and verifies it started. Safe to re-run any time.
3. **A pushed release tag** — see [Releases](#releases) below; downloads
   a prebuilt binary from GitHub rather than building locally.

**Manual equivalent** (what both scripted paths actually do, kept here
for reference): build with `make build-linux-amd64` or
`build-linux-arm64`, create a system `archangel` user, copy the binary to
`/opt/archangel/archangeld`, `archangel.service` to
`/etc/systemd/system/`, and a real `config.yaml` to
`/etc/archangel/config.yaml` with `bind_addr` set to the WireGuard
interface IP — never `0.0.0.0` or the box's public IP.

## Uninstalling

`infra/scripts/uninstall.sh [app_port] [wg_port]` reverses the WireGuard
+ archangeld install: stops and removes the `archangel` systemd service,
the binary and `/etc/archangel` (config + token store), and tears down
WireGuard entirely (interface, `wg0.conf`, generated keys, the firewall
ports opened for both) — the server stops being reachable over the
tunnel at all. It deliberately does **not** touch what
`baseline_setup.sh` did (installed packages, the swapfile, general ufw/
SSH posture) — reverting OS-level baseline changes safely is out of
scope. Safe to re-run; every removal tolerates the thing it's removing
already being gone.

In-app: Settings' "Danger zone" section (visible once paired) has an
"Uninstall backend" button that runs this same script over SSH — same
connection machinery as the setup wizard and backend update flow
(`VpsSetupService.uninstall()`), gated behind an explicit typed
confirmation since it's irreversible from the app. On success the app
also forgets its own pairing/WireGuard state for that server, since it
no longer exists.

## Releases

One tag-triggered GitHub Actions workflow,
[`.github/workflows/release.yml`](../../.github/workflows/release.yml),
builds and publishes to GitHub Releases. The tag's suffix decides scope
(the leading version number is always the release-event label, matching
`VERSION`'s `ARCHANGEL` line on a clean tag - the actual per-component
version always comes from `VERSION`'s own `BACKEND`/`FRONTEND` lines,
never from the tag number itself):

| Tag shape | Builds |
|---|---|
| `vX.Y.Z-b` | backend only (`archangeld-amd64`, `archangeld-arm64`) |
| `vX.Y.Z-f` | frontend only (macOS, Windows, Android) |
| `vX.Y.Z` | both |

```bash
git tag v0.3.6 && git push origin v0.3.6
```

Every run also generates and publishes `version-manifest.json` - the
file `UpdateCheckService` (frontend) fetches to know the latest
version of each component and whether the currently-running
app/backend are behind. Its freeze logic matters: a `-b`-only release
freezes the frontend's reported version at whatever the *previous*
release actually shipped (not just whatever `VERSION`'s `FRONTEND` line
happens to say in the working tree), so a backend-only release never
makes the app think the frontend needs updating, and vice versa for
`-f`. See the workflow's `plan` job for the exact freeze rules, and
`backend_tag`/`frontend_tag` in the manifest for which release's assets
actually carry each component's binary (the version number can stay
frozen across several releases in a row, so the binary itself may live
on an older release than "latest").

## Testing the terminal endpoint manually

`curl` can't drive a full WebSocket session. Recommended: `websocat` (`brew install websocat`) —
```bash
websocat "ws://10.10.0.1:8443/ws/terminal?token=<your-token>"
```
then send `{"type":"resize","cols":100,"rows":30}` followed by
`{"type":"stdin","data":"<base64 of your command + \n>"}`, and confirm you
get `stdout` frames back and an `exit` frame when the shell exits.
