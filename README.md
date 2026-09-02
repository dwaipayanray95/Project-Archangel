# Project Archangel

Personal cloud infrastructure + the tools to control it — the umbrella project for everything Archangel needs.

This repo is a **monorepo**: each top-level folder is a self-contained piece, with its own README for depth. This file is just the map.

---

## Structure

| Folder | What it is |
|---|---|
| [`infra/`](infra/README.md) | The Oracle Cloud (OCI) VPS setup and **recovery runbook**. If the server dies or a fresh account is needed, everything to rebuild it from scratch lives there — account/region details, SSH access, the OCI CLI setup, and the capacity-scavenging retry system (local script + scheduled GitHub Actions workflow) used to actually get an Always-Free Ampere A1 instance allocated. |
| `app/` | *(not started yet)* The Archangel control app — decided stack: **Go backend** (SSH bridge, resource watchdog, file browser) + **Flutter frontend** (Android-first). Will get its own README once work begins. |

## Current status

- **Ampere A1 instance:** not yet allocated — retry automation is live and chasing it (see [`infra/README.md`](infra/README.md) section 8)
- **AMD Micro instance (`Archangel-Mk1`):** running, baseline setup complete — updated, 2GB swap, tmux, `ufw` firewall (SSH-only) (see [`infra/README.md`](infra/README.md) section 9). Same baseline procedure will be repeated on the Ampere box once it lands
- **Control app:** stack decided (Go + Flutter), not yet started

---
*Last updated: 2026-09-01*
