# Project Archangel

Personal cloud infrastructure + the tools to control it — the umbrella project for everything Archangel needs.

This repo is a **monorepo**: each top-level folder is a self-contained piece, with its own README for depth. This file is just the map.

---

## Structure

| Folder | What it is |
|---|---|
| [`infra/`](infra/README.md) | The Oracle Cloud (OCI) VPS setup and **recovery runbook**. If the server dies or a fresh account is needed, everything to rebuild it from scratch lives there — account/region details, SSH access, the OCI CLI setup, and the capacity-scavenging retry system (local script + scheduled GitHub Actions workflow) used to actually get an Always-Free Ampere A1 instance allocated. |
| [`app/backend/`](app/backend/README.md) | The Archangel control-plane API — **Go**, single static binary. Milestone 1 (auth + live terminal over WebSocket) deployed to `Archangel-Mk1` and verified working over WireGuard. |
| `app/frontend/` | *(not started yet)* The **Flutter** app (Android-first) that talks to `app/backend/`. |

## Current status

- **Ampere A1 instance:** not yet allocated — retry automation is live and chasing it (see [`infra/README.md`](infra/README.md) section 8)
- **AMD Micro instance (`Archangel-Mk1`):** running, baseline setup complete, WireGuard fully working (server + phone/mac/windows peers; phone/windows still need pairing — only Mac verified so far), backend deployed and reachable over the tunnel (see [`infra/README.md`](infra/README.md) sections 9-11 for the setup, and its incident notes for two real firewall issues hit and fixed along the way). Same procedure will be repeated on the Ampere box once it lands, via [`infra/scripts/install-archangel.sh`](infra/scripts/install-archangel.sh)
- **Backend (`app/backend/`):** Milestone 1 (auth, live PTY terminal over WebSocket) deployed and verified end-to-end over the real network — health endpoint and a real shell session both confirmed working from a paired Mac
- **Frontend (`app/frontend/`):** not started

---
*Last updated: 2026-09-01*
