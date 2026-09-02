#!/bin/bash
# Master setup entrypoint for a fresh Project Archangel instance (Ampere A1
# or AMD Micro). Run this once on a brand-new box to get it from "just
# launched" to "fully set up" in one command:
#
#   git clone https://github.com/dwaipayanray95/Project-Archangel.git
#   cd Project-Archangel
#   ./infra/scripts/install-archangel.sh
#
# This is a thin orchestrator, not a monolith - it calls the individual
# setup scripts in infra/scripts/ in order. Each of those stays independently
# runnable and has its own re-run semantics (baseline_setup.sh is always
# safe to re-run; wireguard_setup.sh refuses to re-run without --force,
# since re-running it would silently invalidate every already-paired
# device). Keeping them separate means any one piece can be re-run in
# isolation later without repeating everything else - e.g. adding a 4th
# WireGuard peer, or re-deploying just the backend after a code change.
#
# As new milestones land (see the app/backend build plan), this script
# grows a new step each time - it's meant to be the canonical "how do I set
# this box up" answer, kept current as the project grows, not a one-time
# snapshot of what setup looked like on one particular day.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "############################################"
echo "# Project Archangel - full instance setup"
echo "############################################"
echo ""

echo "==> [1/2] Baseline (update, swap, tmux, ufw SSH-only)"
"$SCRIPT_DIR/baseline_setup.sh"
echo ""

echo "==> [2/2] WireGuard (server + phone/mac/windows peers)"
if [[ -f /etc/wireguard/wg0.conf ]]; then
  echo "    /etc/wireguard/wg0.conf already exists - skipping to avoid"
  echo "    invalidating already-paired devices. To force regeneration,"
  echo "    run: $SCRIPT_DIR/wireguard_setup.sh --force"
else
  "$SCRIPT_DIR/wireguard_setup.sh"
fi
echo ""

# ---------------------------------------------------------------------------
# Next milestone's step goes here once it exists: building and deploying
# app/backend's archangeld binary + systemd unit. Not added yet because
# that deployment tooling (build, scp/transfer, install the .service file,
# gen-token flow) hasn't been built and verified yet - see app/backend's
# milestone plan. Adding a step here before that tooling actually exists
# and is tested would be committing untested instructions, which is exactly
# the kind of silent-failure risk this whole setup process has already
# been bitten by twice (see infra/README.md's WireGuard section).
# ---------------------------------------------------------------------------

echo "############################################"
echo "# Baseline + WireGuard setup complete."
echo "# Remaining manual step: open 51820/udp in the OCI Console's"
echo "# Security List (VCN-level firewall) - ufw alone isn't enough,"
echo "# see infra/README.md."
echo "############################################"
