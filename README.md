# Project Archangel

Personal cloud infrastructure + the tools to control it — the umbrella project for everything Archangel needs.

This repo is a **monorepo**: each top-level folder is a self-contained piece, with its own README for depth. This file is just the map.

---

## Structure

| Folder | What it is |
|---|---|
| [`infra/`](infra/README.md) | The Oracle Cloud (OCI) VPS setup and **recovery runbook**. If the server dies or a fresh account is needed, everything to rebuild it from scratch lives there — account/region details, SSH access, the OCI CLI setup, and the capacity-scavenging retry system (local script + scheduled GitHub Actions workflow) used to actually get an Always-Free Ampere A1 instance allocated. |
| `app/` | *(not started yet)* The Archangel control app — a personal control panel / gateway into the server: SSH-backed terminal, status, and eventually a proper UI, Android-first. Will get its own README once work begins. |

## Current status

- Ampere A1 instance: retry automation is live and running (see [`infra/README.md`](infra/README.md) section 7)
- AMD Micro instance: not yet provisioned — can be launched immediately (no capacity scarcity issue for that shape), used as a starting point while waiting on Ampere
- Control app: not started

---
*Last updated: 2026-09-01*
