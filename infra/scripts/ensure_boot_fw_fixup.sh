#!/bin/bash
# Ensures allow_port_before_reject.sh (for the given port/proto) re-runs on
# every boot, not just right now. `nft insert rule` is a live, in-kernel-
# only change - nothing writes it to a file that reloads at boot, and
# nothing was found on Archangel-Mk1 that reapplies the original pre-ufw
# catch-all-reject ruleset at boot either (see infra/README.md section 10),
# so without this, a reboot could silently undo the whole fix.
#
# Usage: ./ensure_boot_fw_fixup.sh <port> [tcp|udp]
#
# Safe to re-run for multiple ports: each call adds its port to a shared
# list (/etc/archangel/fw_ports.txt) that one shared systemd oneshot
# service iterates over at boot - not one service per port.
set -euo pipefail

PORT="${1:?Usage: $0 <port> [tcp|udp]}"
PROTO="${2:-tcp}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INSTALLED_SCRIPT="/usr/local/sbin/allow_port_before_reject.sh"
PORTS_FILE="/etc/archangel/fw_ports.txt"
SERVICE_FILE="/etc/systemd/system/archangel-fw-fixup.service"

echo "==> Ensuring the fix script is installed at $INSTALLED_SCRIPT"
sudo mkdir -p /etc/archangel
sudo cp "$SCRIPT_DIR/allow_port_before_reject.sh" "$INSTALLED_SCRIPT"
sudo chmod 755 "$INSTALLED_SCRIPT"

echo "==> Registering ${PROTO}/${PORT} in $PORTS_FILE"
sudo touch "$PORTS_FILE"
if sudo grep -qxF "${PORT} ${PROTO}" "$PORTS_FILE" 2>/dev/null; then
  echo "    Already registered."
else
  echo "${PORT} ${PROTO}" | sudo tee -a "$PORTS_FILE" > /dev/null
  echo "    Added."
fi

echo "==> Installing the boot-time systemd unit"
sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Re-apply Archangel firewall exceptions ahead of the pre-ufw catch-all reject rule
# Deliberately ordered to run LATE (after ufw, after network is fully up),
# not early - we never identified what actually creates the pre-existing
# catch-all reject rule in the first place (see infra/README.md section
# 10), so if anything recreates it during boot, this needs to run after
# that, not race ahead of it.
After=network-online.target ufw.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'while read -r port proto; do [ -n "\$port" ] && ${INSTALLED_SCRIPT} "\$port" "\$proto"; done < ${PORTS_FILE}'

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable archangel-fw-fixup.service

# Run it now too, not just enable it for next boot - so the current fix
# (for whatever port was just passed) is actually applied immediately,
# not left waiting for a reboot to take effect.
echo "==> Applying now (not just enabling for next boot)"
sudo systemctl start archangel-fw-fixup.service

if sudo systemctl is-enabled --quiet archangel-fw-fixup.service; then
  echo "    Verified: archangel-fw-fixup.service is enabled - will re-run at every boot."
else
  echo "ERROR: archangel-fw-fixup.service did not enable correctly."
  exit 1
fi
