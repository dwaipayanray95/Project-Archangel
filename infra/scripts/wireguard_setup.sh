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

# fix_pre_ufw_iptables_gotcha <port>: some OCI Ubuntu images ship a
# pre-existing iptables ruleset (ACCEPT established/related, ICMP, loopback,
# new TCP/22, then a catch-all REJECT) that's separate from and evaluated
# BEFORE ufw's own chains. `ufw allow <port>` looks completely correct in
# `ufw status` and the service correctly shows as listening in `ss`, but
# every packet still gets rejected by this earlier rule first - discovered
# the hard way on Archangel-Mk1 (see infra/README.md section 10's incident
# notes for the full diagnosis story: ufw-* chains stayed at 0 hits while
# the REJECT rule's counter climbed).
#
# This only inserts a rule if that specific pattern is actually present -
# it does not assume every box has this quirk (a from-scratch non-OCI box,
# or a future OCI image without this default, should see this as a no-op).
fix_pre_ufw_iptables_gotcha() {
  local port="$1"

  # Non-verbose `-L -n --line-numbers` columns are: num target prot opt
  # source destination [extra]. Find the first catch-all REJECT/DROP rule
  # (protocol "all", i.e. not scoped to a specific port/protocol) - that's
  # the one sitting in front of ufw's chains.
  local reject_line
  reject_line=$(sudo iptables -L INPUT -n --line-numbers | awk \
    '($2=="REJECT" || $2=="DROP") && $3=="all" { print $1; exit }')

  if [[ -z "$reject_line" ]]; then
    echo "    No pre-ufw catch-all REJECT/DROP rule detected - nothing to fix here."
    return 0
  fi

  echo "    Found a catch-all $(sudo iptables -L INPUT -n --line-numbers | awk -v l="$reject_line" '$1==l{print $2}') rule at INPUT line $reject_line that runs BEFORE ufw's own chains (see infra/README.md section 10)."

  local existing_line
  existing_line=$(sudo iptables -L INPUT -n --line-numbers | awk -v port="$port" \
    '$0 ~ ("udp dpt:" port) && $2=="ACCEPT" { print $1; exit }')

  if [[ -n "$existing_line" && "$existing_line" -lt "$reject_line" ]]; then
    echo "    ACCEPT rule for udp/$port already precedes it (line $existing_line) - nothing to insert."
  else
    echo "    Inserting ACCEPT udp/$port at line $reject_line, ahead of the reject rule."
    sudo iptables -I INPUT "$reject_line" -p udp --dport "$port" -j ACCEPT
  fi

  echo "    Ensuring the fix survives a reboot (iptables-persistent)..."
  if ! dpkg -s iptables-persistent > /dev/null 2>&1; then
    sudo DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent
  fi
  sudo netfilter-persistent save

  # Verify, not assume - re-read the live rules after the change instead of
  # trusting the insert succeeded.
  local new_reject_line new_accept_line
  new_reject_line=$(sudo iptables -L INPUT -n --line-numbers | awk \
    '($2=="REJECT" || $2=="DROP") && $3=="all" { print $1; exit }')
  new_accept_line=$(sudo iptables -L INPUT -n --line-numbers | awk -v port="$port" \
    '$0 ~ ("udp dpt:" port) && $2=="ACCEPT" { print $1; exit }')

  if [[ -z "$new_accept_line" || -z "$new_reject_line" || "$new_accept_line" -ge "$new_reject_line" ]]; then
    echo "ERROR: verification failed - ACCEPT rule for udp/$port is not correctly positioned before the reject rule. Aborting."
    exit 1
  fi
  if [[ "$(systemctl is-enabled netfilter-persistent 2>/dev/null)" != "enabled" ]]; then
    echo "ERROR: netfilter-persistent is not enabled - this fix would not survive a reboot. Aborting."
    exit 1
  fi
  echo "    Verified: ACCEPT at line $new_accept_line precedes reject at line $new_reject_line, and the fix is persisted."
}

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

fix_pre_ufw_iptables_gotcha "$WG_PORT"

echo "==> Done. Current tunnel state:"
sudo wg show

echo ""
echo "Next steps:"
echo "  - Phone: sudo qrencode -t ansiutf8 < $WG_DIR/phone.conf, scan with the WireGuard app"
echo "  - Mac/Windows: copy $WG_DIR/{mac,windows}.conf off the server (they're root:600,"
echo "    e.g. 'sudo cp $WG_DIR/mac.conf ~/mac.conf && sudo chown \$USER ~/mac.conf' then scp it off)"
echo "    and import into the WireGuard desktop app."
