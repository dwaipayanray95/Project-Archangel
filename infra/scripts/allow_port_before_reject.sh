#!/bin/bash
# Ensures TCP or UDP traffic on a given port reaches an ACCEPT decision
# before hitting the pre-existing catch-all REJECT rule some OCI Ubuntu
# images ship in the kernel's raw INPUT chain - a rule that sits ahead of
# (and is completely independent from) ufw's own chains. `ufw allow <port>`
# alone is NOT sufficient on an affected box: ufw's rules only apply within
# its own ufw-* chains, and those turned out to be unreachable dead code on
# Archangel-Mk1 - the catch-all REJECT terminates chain processing before
# anything ever jumps into ufw's chains at all. See infra/README.md section
# 10 for the full incident writeup.
#
# Usage: ./allow_port_before_reject.sh <port> [tcp|udp]
#
# Uses `nft` directly, addressing rules by their stable numeric handle -
# NOT `iptables -L ... --line-numbers`. That was today's other real
# discovery: once ufw's native nft-managed rules and manual `iptables`
# inserts have both touched the same ruleset in one session, the legacy
# `iptables -L` compatibility view can show duplicate/stale entries and
# unreliable line numbers (confirmed directly: it reported a second,
# nonexistent REJECT rule that `nft list ruleset` proved was never really
# there). `nft`'s own handles are the ruleset's actual identity, not a
# recomputed display artifact, so they don't have this problem.
#
# Safe to re-run: checks whether an ACCEPT for this exact port already
# exists ahead of the reject rule before inserting anything.
set -euo pipefail

PORT="${1:?Usage: $0 <port> [tcp|udp]}"
PROTO="${2:-tcp}"

if [[ "$PROTO" != "tcp" && "$PROTO" != "udp" ]]; then
  echo "ERROR: protocol must be 'tcp' or 'udp', got '$PROTO'"
  exit 1
fi

# Find the first catch-all REJECT/DROP rule in the real ip/filter/INPUT
# chain - matched on having no protocol-specific match at all, i.e. it's
# unconditional (unlike our own port-scoped rules).
REJECT_HANDLE=$(sudo nft -a list chain ip filter INPUT 2>/dev/null \
  | awk '/reject with|^\s*drop\s*$|counter.*\bdrop\b/ && !/dport|sport|dst-type|ct state/ {
      for (i=1;i<=NF;i++) if ($i=="handle") print $(i+1)
      exit
    }')

if [[ -z "$REJECT_HANDLE" ]]; then
  echo "No unconditional catch-all reject/drop rule found in ip filter INPUT - nothing to fix."
  exit 0
fi
echo "Found catch-all reject rule at handle $REJECT_HANDLE."

# Does an ACCEPT for this exact port already exist, and does it appear
# before the reject rule in the chain's actual (evaluation) order? `nft -a
# list` prints rules in evaluation order, so a simple "which comes first in
# the output" check is sufficient - no separate ordering logic needed.
# `|| true` on each grep: under `set -e -o pipefail`, grep finding no match
# (its normal, expected exit code 1 when the port rule doesn't exist yet -
# exactly the common case on a fresh box) would otherwise abort the whole
# script here instead of just leaving the variable empty.
EXISTING_LINE=$(sudo nft -a list chain ip filter INPUT 2>/dev/null | { grep -n "${PROTO} dport ${PORT} accept" || true; } | head -1 | cut -d: -f1)
REJECT_LINE=$(sudo nft -a list chain ip filter INPUT 2>/dev/null | { grep -n "handle ${REJECT_HANDLE}\$" || true; } | head -1 | cut -d: -f1)

if [[ -n "$EXISTING_LINE" && -n "$REJECT_LINE" && "$EXISTING_LINE" -lt "$REJECT_LINE" ]]; then
  echo "ACCEPT rule for ${PROTO}/${PORT} already precedes the reject rule - nothing to insert."
else
  echo "Inserting ACCEPT ${PROTO}/${PORT} ahead of handle ${REJECT_HANDLE}."
  sudo nft insert rule ip filter INPUT handle "$REJECT_HANDLE" "${PROTO} dport ${PORT} accept"
fi

# Verify, not assume - re-check the live state rather than trusting the
# insert succeeded, same principle as everywhere else in this repo's
# scripts.
NEW_LINE=$(sudo nft -a list chain ip filter INPUT 2>/dev/null | { grep -n "${PROTO} dport ${PORT} accept" || true; } | head -1 | cut -d: -f1)
NEW_REJECT_LINE=$(sudo nft -a list chain ip filter INPUT 2>/dev/null | { grep -n "handle ${REJECT_HANDLE}\$" || true; } | head -1 | cut -d: -f1)
if [[ -z "$NEW_LINE" || -z "$NEW_REJECT_LINE" || "$NEW_LINE" -ge "$NEW_REJECT_LINE" ]]; then
  echo "ERROR: verification failed - ${PROTO}/${PORT} ACCEPT is not correctly positioned before the reject rule."
  exit 1
fi
echo "Verified: ${PROTO}/${PORT} is allowed ahead of the catch-all reject."
