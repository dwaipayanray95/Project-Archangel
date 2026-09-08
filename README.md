# Project Archangel

Personal cloud infrastructure + the tools to control it — the umbrella project for everything Archangel needs. The goal: point the app at a fresh VPS and a private key, and have the app itself become the "operating system" for that server — setup, pairing, terminal, files, monitoring, and self-updating, all over a WireGuard tunnel, no manual SSH required after the initial handoff.

This repo is a **monorepo**: each top-level folder is a self-contained piece, with its own README for depth. This file is just the map.

---

## Structure

| Folder | What it is |
|---|---|
| [`infra/`](infra/README.md) | The Oracle Cloud (OCI) VPS setup and **recovery runbook** — account/region details, SSH access, OCI CLI setup, the capacity-scavenging retry system for Ampere A1 allocation, and the baseline/WireGuard shell scripts that both the manual runbook and the in-app setup wizard (below) actually execute. |
| [`app/backend/`](app/backend/README.md) | `archangeld` — the Go control-plane API, single static binary, reachable only over WireGuard. Implements terminal, system monitoring, and a jailed file browser; versioned and released independently of the frontend. |
| [`app/frontend/`](app/frontend/README.md) | The Flutter app (Android/Windows/macOS/Linux from one codebase) — the GUI for `archangeld`, and also the thing that *sets up* a fresh server via SSH so nobody has to. |

## Current status

**Deployed and working end-to-end on real hardware:**
- WireGuard tunnel (server + macOS peer verified for real; Android/Windows wired but unverified on real devices)
- `archangeld` control plane: token-authed pairing (`archangeld pair`), a real PTY terminal over WebSocket, system monitoring (CPU/memory/disk/process list, with kill/renice), and a jailed file browser (list/preview/download, confined to a configured `files_root` both textually and through symlinks)
- In-app VPS setup wizard: SSHes into a fresh Ubuntu/Debian server, runs the real `infra/scripts/*.sh`, installs the systemd service, and auto-pairs the app — no manual SSH needed for a first-time setup. Hardened per a `/code-review` pass (SSH host-key TOFU verification, no shell-injection paths, biometric/PIN gate on a remembered key)
- In-app backend updates: tapping an "update available" badge in Settings re-SSHes in (reusing the wizard's connection/credentials) to download, verify, and install a new `archangeld` build, with automatic rollback if the new version doesn't come up healthy — `archangeld` itself runs unprivileged and deliberately can't self-update over HTTP
- Version visibility + release automation: a shared root [`VERSION`](VERSION) file tracks the project/frontend/backend versions independently; one tag-triggered GitHub Actions pipeline ([`release.yml`](.github/workflows/release.yml)) builds and publishes whichever component(s) a tag's suffix names (`-b` backend, `-f` frontend, no suffix = both) to GitHub Releases, and the app checks that automatically to show "update available" per component

**Still mock data / not started:**
- Containers and DevOps screens (no backend routes exist yet)
- Android and Windows real-device verification (code is written and `flutter analyze`-clean, never run on real hardware)
- Second Ampere A1 instance — allocation retry automation is live, not yet landed

**Known rough edges:** see each component's README (below) for specifics — nothing is silently broken, but not everything is verified against real hardware yet.

## Where to go next

- Setting up or recovering the VPS itself → [`infra/README.md`](infra/README.md)
- Backend API, routes, auth, versioning/release scheme → [`app/backend/README.md`](app/backend/README.md)
- Frontend architecture, what's real vs. mock, the setup wizard and update flow → [`app/frontend/README.md`](app/frontend/README.md) and [`app/frontend/WORKING.md`](app/frontend/WORKING.md)
- WireGuard per-platform implementation details → [`app/frontend/WIREGUARD.md`](app/frontend/WIREGUARD.md)

## License

This project is licensed under [The Awesome License v1 (TALv1)](LICENSE) — free
for personal/non-profit use; commercial use requires either open-sourcing your
project or a commercial agreement with the author. This is a **source-available**
license, not OSI-approved open source.

---
*Last updated: 2026-09-08*
