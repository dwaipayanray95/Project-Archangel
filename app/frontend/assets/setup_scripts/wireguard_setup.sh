#!/bin/bash
# Sets up WireGuard on this box: server keypair, one peer per device in
# PEERS below, server config, per-device config files, firewall rule, and
# starts the tunnel. Run this once on a fresh/rebuilt instance instead of
# following the manual steps in infra/README.md section 10 by hand.
#
# Safe to inspect before running (no destructive default): refuses to touch
# an existing /etc/wireguard/wg0.conf unless --force is passed, so it won't
# silently clobber a working setup and break already-paired devices.
#
# Must run as a user with passwordless sudo (the default "ubuntu" cloud-init
# user). Runs as one continuous script specifically to avoid the sudo
# credential cache expiring mid-setup - which is what actually broke the
# very first manual attempt at this (see the incident notes in
# infra/README.md section 10) and silently wrote broken, empty-keyed config
# files. Every generated value is verified non-empty before use for the
# same reason - trust nothing here, verify everything.
set -euo pipefail

# ===== CONFIG =====
PEERS=("phone" "mac" "windows")
WG_SUBNET="10.10.0"          # server = .1, peers = .2, .3, .4, ...
WG_PORT=51820
WG_DIR="/etc/wireguard"
# =========================================================

FORCE=false
if [[ "${1:-}" == "--force" ]]; then
  FORCE=true
fi

if [[ -f "$WG_DIR/wg0.conf" && "$FORCE" != true ]]; then
  echo "ERROR: $WG_DIR/wg0.conf already exists - refusing to overwrite a working setup."
  echo "If you really want to regenerate everything (this invalidates every"
  echo "already-paired device and they'll all need to re-import their configs),"
  echo "re-run with: $0 --force"
  exit 1
fi

echo "==> Installing wireguard + qrencode"
sudo apt update -qq
sudo apt install -y -qq wireguard qrencode

echo "==> Detecting public IP"
PUBLIC_IP=$(curl -s -4 ifconfig.me || curl -s -4 icanhazip.com)
if [[ -z "$PUBLIC_IP" ]]; then
  echo "ERROR: could not auto-detect this box's public IP. Set PUBLIC_IP manually and re-run."
  exit 1
fi
echo "    Public IP: $PUBLIC_IP"

# require_nonempty <name> <value>: fail loudly instead of silently writing
# a broken config with an empty key, which is exactly what happened by hand.
require_nonempty() {
  local name="$1" value="$2"
  if [[ -z "$value" ]]; then
    echo "ERROR: $name is empty - something failed generating/reading a key. Aborting."
    exit 1
  fi
}

# The pre-ufw catch-all-reject fix lives in its own script now
# (allow_port_before_reject.sh), shared with deploy.sh since the backend
# needs this exact same fix for its own port. See that script and
# infra/README.md section 10 for the full incident writeup - in short:
# a previous version of this fix used `iptables-persistent` to survive
# reboots, which turned out to silently REMOVE the ufw package entirely
# (a real Debian/Ubuntu packaging conflict) the first time it ran. Never
# install iptables-persistent - it is not needed; a plain `nft` rule
# insert is not tied to iptables-persistent's persistence mechanism at
# all, it's just a direct, permanent change to the live ruleset that
# ufw's own presence/absence has no bearing on.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Generating server keypair"
wg genkey | sudo tee "$WG_DIR/server_private.key" > /dev/null
sudo cat "$WG_DIR/server_private.key" | wg pubkey | sudo tee "$WG_DIR/server_public.key" > /dev/null
sudo chmod 600 "$WG_DIR/server_private.key"

SERVER_PRIVKEY=$(sudo cat "$WG_DIR/server_private.key")
SERVER_PUBKEY=$(sudo cat "$WG_DIR/server_public.key")
require_nonempty "server private key" "$SERVER_PRIVKEY"
require_nonempty "server public key" "$SERVER_PUBKEY"

echo "==> Generating peer keypairs: ${PEERS[*]}"
for peer in "${PEERS[@]}"; do
  wg genkey | sudo tee "$WG_DIR/${peer}_private.key" > /dev/null
  sudo cat "$WG_DIR/${peer}_private.key" | wg pubkey | sudo tee "$WG_DIR/${peer}_public.key" > /dev/null
  sudo chmod 600 "$WG_DIR/${peer}_private.key"

  peer_pub=$(sudo cat "$WG_DIR/${peer}_public.key")
  require_nonempty "${peer} public key" "$peer_pub"
done

echo "==> Writing server config ($WG_DIR/wg0.conf)"
{
  echo "[Interface]"
  echo "Address = ${WG_SUBNET}.1/24"
  echo "ListenPort = $WG_PORT"
  echo "PrivateKey = $SERVER_PRIVKEY"

  n=2
  for peer in "${PEERS[@]}"; do
    peer_pub=$(sudo cat "$WG_DIR/${peer}_public.key")
    echo ""
    echo "[Peer]"
    echo "# $peer"
    echo "PublicKey = $peer_pub"
    echo "AllowedIPs = ${WG_SUBNET}.${n}/32"
    n=$((n + 1))
  done
} | sudo tee "$WG_DIR/wg0.conf" > /dev/null
sudo chmod 600 "$WG_DIR/wg0.conf"

echo "==> Writing per-device configs"
n=2
for peer in "${PEERS[@]}"; do
  peer_priv=$(sudo cat "$WG_DIR/${peer}_private.key")
  require_nonempty "${peer} private key (re-read)" "$peer_priv"

  sudo tee "$WG_DIR/${peer}.conf" > /dev/null <<EOF
[Interface]
PrivateKey = $peer_priv
Address = ${WG_SUBNET}.${n}/32

[Peer]
PublicKey = $SERVER_PUBKEY
Endpoint = ${PUBLIC_IP}:${WG_PORT}
AllowedIPs = ${WG_SUBNET}.1/32
PersistentKeepalive = 25
EOF
  sudo chmod 600 "$WG_DIR/${peer}.conf"
  n=$((n + 1))
done

echo "==> Verifying every generated config actually has a non-empty key"
for f in "$WG_DIR/wg0.conf"; do
  while IFS='=' read -r key val; do
    key=$(echo "$key" | tr -d ' ')
    val=$(echo "$val" | tr -d ' ')
    if [[ "$key" == "PrivateKey" || "$key" == "PublicKey" ]]; then
      require_nonempty "$f:$key" "$val"
    fi
  done < <(sudo grep -E '^(PrivateKey|PublicKey)' "$f")
done
for peer in "${PEERS[@]}"; do
  for key in PrivateKey PublicKey; do
    # -f2- (not -f2) - WireGuard base64 keys often end in a literal '='
    # padding character, and cut splits on every delimiter, so -f2 alone
    # would silently truncate that last character off the extracted value.
    val=$(sudo grep "^$key" "$WG_DIR/${peer}.conf" | cut -d'=' -f2- | tr -d ' ')
    require_nonempty "${peer}.conf:$key" "$val"
  done
done
echo "    All keys verified non-empty."

echo "==> Starting the tunnel"
sudo systemctl enable --now wg-quick@wg0
sudo systemctl restart wg-quick@wg0   # restart, not just start, in case --force re-ran on an already-running tunnel

echo "==> Opening $WG_PORT/udp in ufw"
sudo ufw allow "${WG_PORT}/udp" > /dev/null

echo "==> Ensuring ${WG_PORT}/udp reaches an ACCEPT ahead of the pre-ufw catch-all reject"
"$SCRIPT_DIR/allow_port_before_reject.sh" "$WG_PORT" udp
echo "==> Making that fix (and future ones) survive a reboot"
"$SCRIPT_DIR/ensure_boot_fw_fixup.sh" "$WG_PORT" udp

echo "==> Done. Current tunnel state:"
sudo wg show

echo ""
echo "Next steps:"
echo "  - Phone: sudo qrencode -t ansiutf8 < $WG_DIR/phone.conf, scan with the WireGuard app"
echo "  - Mac/Windows: copy $WG_DIR/{mac,windows}.conf off the server (they're root:600,"
echo "    e.g. 'sudo cp $WG_DIR/mac.conf ~/mac.conf && sudo chown \$USER ~/mac.conf' then scp it off)"
echo "    and import into the WireGuard desktop app."
