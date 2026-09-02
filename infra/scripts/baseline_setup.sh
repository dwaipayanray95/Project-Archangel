#!/bin/bash
# Baseline hardening/setup for a fresh Project Archangel instance: system
# update, swap, tmux, and an SSH-only ufw firewall. Matches infra/README.md
# section 9's manual checklist exactly - this is that checklist, scripted.
#
# Safe to re-run: every step checks whether it's already done before acting,
# so running this again on an already-set-up box is a harmless no-op (unlike
# wireguard_setup.sh, which refuses to re-run without --force since
# WireGuard identity/pairing can't be silently regenerated safely).
set -euo pipefail

SWAP_FILE="/swapfile"
SWAP_SIZE_GB=2

echo "==> Updating system packages"
sudo apt update -qq
sudo apt upgrade -y -qq

echo "==> Swap"
if sudo swapon --show | grep -q "$SWAP_FILE"; then
  echo "    Swap already active at $SWAP_FILE - skipping."
else
  sudo fallocate -l "${SWAP_SIZE_GB}G" "$SWAP_FILE"
  sudo chmod 600 "$SWAP_FILE"
  sudo mkswap "$SWAP_FILE" > /dev/null
  sudo swapon "$SWAP_FILE"
  if ! grep -q "^$SWAP_FILE " /etc/fstab; then
    echo "$SWAP_FILE none swap sw 0 0" | sudo tee -a /etc/fstab > /dev/null
  fi
  echo "    Added ${SWAP_SIZE_GB}G swap at $SWAP_FILE."
fi

echo "==> tmux"
if command -v tmux > /dev/null; then
  echo "    tmux already installed - skipping."
else
  sudo apt install -y -qq tmux
fi

echo "==> ufw (SSH-only baseline)"
if ! command -v ufw > /dev/null; then
  sudo apt install -y -qq ufw
fi
sudo ufw allow OpenSSH > /dev/null || sudo ufw allow 22/tcp > /dev/null
if sudo ufw status | grep -q "Status: active"; then
  echo "    ufw already active."
else
  sudo ufw --force enable > /dev/null
fi

echo "==> Done. Current state:"
free -h
sudo ufw status
