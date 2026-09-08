#!/bin/bash
# Reverses infra/scripts/wireguard_setup.sh + app/backend/deploy.sh /
# VpsSetupService.run(): stops and removes archangeld (service, binary,
# config, token store) and tears down WireGuard (interface, config, keys,
# firewall port) - this server stops being reachable over the tunnel at
# all once this finishes.
#
# Deliberately does NOT touch what infra/scripts/baseline_setup.sh did
# (installed packages, the swapfile, general ufw/SSH posture) - reverting
# OS-level baseline changes safely is a much bigger, riskier surface than
# archangeld/WireGuard themselves, and nothing about those changes is
# specific to Archangel being installed.
#
# Safe to re-run: every step tolerates the thing it's removing already
# being gone (`|| true` on stop/delete commands), same idempotency
# discipline as the setup scripts.
set -uo pipefail

APP_PORT="${1:-8443}"
WG_PORT="${2:-51820}"

echo "==> Stopping and removing the archangel service"
sudo systemctl disable --now archangel >/dev/null 2>&1 || true
sudo rm -f /etc/systemd/system/archangel.service
sudo systemctl daemon-reload

echo "==> Removing archangeld binary and config"
sudo rm -rf /opt/archangel
sudo rm -rf /etc/archangel

echo "==> Stopping and removing WireGuard"
sudo systemctl disable --now wg-quick@wg0 >/dev/null 2>&1 || true
sudo rm -f /etc/wireguard/wg0.conf
sudo rm -f /etc/wireguard/server_private.key /etc/wireguard/server_public.key
sudo rm -f /etc/wireguard/*_private.key /etc/wireguard/*_public.key
sudo rm -f /etc/wireguard/*.conf

echo "==> Closing firewall ports"
sudo ufw delete allow "${WG_PORT}/udp" >/dev/null 2>&1 || true
sudo ufw delete allow in on wg0 to any port "${APP_PORT}" proto tcp >/dev/null 2>&1 || true

# Best-effort: remove the direct nft ACCEPT rules allow_port_before_reject.sh
# inserted for these two ports, if still present. Not fatal if this can't
# find a match - a stray allow rule for a port nothing is listening on
# anymore is inert, not a security hole.
for port_proto in "${WG_PORT}/udp" "${APP_PORT}/tcp"; do
  port="${port_proto%/*}"
  proto="${port_proto#*/}"
  handle=$(sudo nft -a list chain ip filter INPUT 2>/dev/null \
    | awk -v p="$port" -v pr="$proto" '$0 ~ pr" dport "p" accept" { for (i=1;i<=NF;i++) if ($i=="handle") print $(i+1) }')
  for h in $handle; do
    sudo nft delete rule ip filter INPUT handle "$h" 2>/dev/null || true
  done
done

echo "==> Removing the archangel system user"
sudo userdel archangel >/dev/null 2>&1 || true

echo "==> Done. archangeld and WireGuard have been removed from this server."
echo "    Baseline OS changes (packages, swapfile, SSH-only ufw rule) were left in place."
