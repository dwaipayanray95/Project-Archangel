# Archangel Backend

The Go control-plane server: a single static binary exposing terminal, file,
service, resource, Docker, and OCI instance controls to the Flutter app —
reachable only over a WireGuard tunnel, never the public internet.

Full architecture and API design: see the plan this was built from (route
table, WebSocket frame protocol, WireGuard setup, systemd unit design).

## Status: Milestone 1 (skeleton, auth, terminal)

Implemented:
- `/api/v1/health` — unauthenticated liveness check
- `/ws/terminal` — real interactive PTY shell over WebSocket, token-authed
- Single shared token auth (`X-Archangel-Token` header or `?token=` query param for the WS handshake)

Not yet implemented (later milestones): files, services, stats/watchdog, Docker, OCI instance control.

## Local development

```bash
cp config.example.yaml config.yaml
go run ./cmd/archangeld gen-token   # prints a token + the token_hash line to paste into config.yaml
make run
```

`bind_addr` in `config.yaml` should stay `127.0.0.1` for local dev — it only
becomes the WireGuard interface IP once actually deployed to the server.

## Building for deployment

```bash
make build-linux-amd64   # Archangel-Mk1 (AMD Micro)
make build-linux-arm64   # Ampere A1, once allocated
```

Deploy the resulting binary to `/opt/archangel/archangeld` on the server,
`archangel.service` to `/etc/systemd/system/`, and a real `config.yaml` to
`/etc/archangel/config.yaml` with `bind_addr` set to the WireGuard interface
IP — never `0.0.0.0` or the box's public IP.

## Testing the terminal endpoint manually

`curl` can't drive a full WebSocket session. A quick way to sanity-check:
open `/ws/terminal?token=<your-token>` from a small Go or `websocat` client,
send `{"type":"resize","cols":100,"rows":30}` then
`{"type":"stdin","data":"<base64 of your command + \n>"}`, and confirm you
get `stdout` frames back and an `exit` frame when the shell exits.
