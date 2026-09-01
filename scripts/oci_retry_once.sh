#!/bin/bash
# Single-attempt variant of oci_retry.sh, designed for GitHub Actions.
# Each workflow run is one attempt; the workflow's cron schedule provides the retry loop.
#
# Exit codes:
#   0  - instance already exists or was just created (the goal is achieved -
#        the caller should stop scheduling further runs)
#   75 - out of capacity / rate limited (expected, try again next run)
#   1  - unexpected error (worth a look)
set -uo pipefail

# ===== CONFIG - same values as scripts/oci_retry.sh =====
COMPARTMENT_ID="ocid1.tenancy.oc1..aaaaaaaabarxx7mbciow4ma43m4gl5q6pcbenxa3xynmq7eztbr3sgnfhfia"
AD="EBDD:AP-MUMBAI-1-AD-1"
SUBNET_ID="ocid1.subnet.oc1.ap-mumbai-1.aaaaaaaayuhquek4rhpeu6hyv4gwmvfbiwyetlqtrdkrjeg2z3soauq5i2fq"
IMAGE_ID="ocid1.image.oc1.ap-mumbai-1.aaaaaaaamtc6jgk5qnf36vkudldlyn3fhmngilbepfgxdir3v3hlujs2gcbq"
DISPLAY_NAME="project-archangel"
SHAPE="VM.Standard.A1.Flex"
OCPUS=1
MEMORY_GB=6
# SSH_KEY_PATH must be set as an env var, pointing to a file containing the public key
# (written from the OCI_SSH_PUBLIC_KEY secret before this script runs)
# =========================================================

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Checking for an existing instance named '$DISPLAY_NAME'..."

# Deliberately not filtered to --lifecycle-state RUNNING: a freshly launched
# instance sits in PROVISIONING/STARTING for a bit before it's RUNNING, and a
# RUNNING-only filter would miss it during that window and attempt a second
# launch. Treat anything except TERMINATED/TERMINATING as "already handled".
existing=$(oci compute instance list \
  --compartment-id "$COMPARTMENT_ID" \
  --display-name "$DISPLAY_NAME" \
  </dev/null 2>&1)

if echo "$existing" | grep '"lifecycle-state"' | grep -qv -E 'TERMINATED|TERMINATING'; then
  echo "Instance already exists (provisioning or running) - nothing to do."
  exit 0
fi

echo "No running instance found. Attempting launch..."

result=$(oci compute instance launch \
  --compartment-id "$COMPARTMENT_ID" \
  --availability-domain "$AD" \
  --subnet-id "$SUBNET_ID" \
  --image-id "$IMAGE_ID" \
  --shape "$SHAPE" \
  --shape-config "{\"ocpus\": $OCPUS, \"memoryInGBs\": $MEMORY_GB}" \
  --display-name "$DISPLAY_NAME" \
  --assign-public-ip true \
  --ssh-authorized-keys-file "${SSH_KEY_PATH:?SSH_KEY_PATH env var not set}" \
  </dev/null 2>&1)

if echo "$result" | grep -q '"lifecycle-state"'; then
  echo "SUCCESS! Instance created."
  echo "$result"
  exit 0
elif echo "$result" | grep -qi "capacity"; then
  echo "Out of capacity. Will retry on the next scheduled run."
  exit 75
elif echo "$result" | grep -qi "TooManyRequests"; then
  echo "Rate limited. Will retry on the next scheduled run."
  exit 75
else
  echo "Unexpected error - this is NOT the normal out-of-capacity case:"
  echo "$result"
  exit 1
fi
