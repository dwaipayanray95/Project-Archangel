# Archangel Backend

The Go control-plane server: a single static binary exposing terminal, file,
service, resource, Docker, and OCI instance controls to the Flutter app —
reachable only over a WireGuard tunnel, never the public internet.

Full architecture and API design: see the plan this was built from (route
table, WebSocket frame protocol, WireGuard setup, systemd unit design).

## Status: Milestone 1 (skeleton, auth, terminal) — deployed and verified

Implemented:
- `/api/v1/health` — unauthenticated liveness check
- `/ws/terminal` — real interactive PTY shell over WebSocket, token-authed
- Single shared token auth (`X-Archangel-Token` header or `?token=` query param for the WS handshake)

Deployed to `Archangel-Mk1` (2026-09-02) and verified end-to-end over the real network path (not just localhost): health endpoint reachable via the WireGuard IP and confirmed unreachable via the public IP, and a real terminal session (decoded `stdout` frame showing the actual live shell prompt) confirmed working over the tunnel from a paired Mac. See `infra/README.md` section 10 for the firewall issues hit and fixed along the way.

Not yet implemented (later milestones): files, services, stats/watchdog, Docker, OCI instance control.

## Local development

```bash
cp config.example.yaml config.yaml
go run ./cmd/archangeld gen-token   # prints a token + the token_hash line to paste into config.yaml
make run
```

`bind_addr` in `config.yaml` should stay `127.0.0.1` for local dev — it only
becomes the WireGuard interface IP once actually deployed to the server.

## Deploying to a server

**Scripted:** [`deploy.sh`](deploy.sh) — run this from your own machine (Mac, etc.), not on the server itself:
```bash
./deploy.sh
# or override defaults:
SERVER_HOST=1.2.3.4 SERVER_USER=ubuntu SSH_KEY=~/path/to/key ./deploy.sh
```
It builds the binary locally, creates the `archangel` system user + directories on the server if they don't exist yet, copies and installs the binary, generates a fresh auth token **only if `/etc/archangel/config.yaml` doesn't already exist** (re-running never silently rotates an already-paired app's token), installs/updates the systemd service, and verifies it started. The generated token is shown exactly once — save it in a password manager immediately, it's needed to pair the Flutter app and the server never stores it in plaintext.

Safe to re-run any time you've rebuilt the binary — it'll redeploy the new build and restart the service without touching an existing config/token.

**Manual equivalent** (what the script actually does, kept here for reference): build with `make build-linux-amd64` (Archangel-Mk1) or `make build-linux-arm64` (Ampere, once allocated), create a system `archangel` user, copy the binary to `/opt/archangel/archangeld`, `archangel.service` to `/etc/systemd/system/`, and a real `config.yaml` to `/etc/archangel/config.yaml` with `bind_addr` set to the WireGuard interface IP — never `0.0.0.0` or the box's public IP.

## Testing the terminal endpoint manually

`curl` can't drive a full WebSocket session. Recommended: `websocat` (`brew install websocat`) —
```bash
websocat "ws://10.10.0.1:8443/ws/terminal?token=<your-token>"
```
then send `{"type":"resize","cols":100,"rows":30}` followed by
`{"type":"stdin","data":"<base64 of your command + \n>"}`, and confirm you
get `stdout` frames back and an `exit` frame when the shell exits.
