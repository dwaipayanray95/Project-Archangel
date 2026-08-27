#!/bin/bash

# ===== CONFIG - already filled in with your values =====
COMPARTMENT_ID="ocid1.tenancy.oc1..aaaaaaaabarxx7mbciow4ma43m4gl5q6pcbenxa3xynmq7eztbr3sgnfhfia"
AD="EBDD:AP-MUMBAI-1-AD-1"
SUBNET_ID="ocid1.subnet.oc1.ap-mumbai-1.aaaaaaaayuhquek4rhpeu6hyv4gwmvfbiwyetlqtrdkrjeg2z3soauq5i2fq"
IMAGE_ID="ocid1.image.oc1.ap-mumbai-1.aaaaaaaamtc6jgk5qnf36vkudldlyn3fhmngilbepfgxdir3v3hlujs2gcbq"
SSH_KEY_PATH="$HOME/Downloads/project-archangel-public.key.pub"
DISPLAY_NAME="project-archangel"
SHAPE="VM.Standard.A1.Flex"
OCPUS=1
MEMORY_GB=6
RETRY_INTERVAL_SECONDS=120
# =========================================================

attempt=1
while true; do
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Attempt #$attempt..."

  result=$(oci compute instance launch \
    --compartment-id "$COMPARTMENT_ID" \
    --availability-domain "$AD" \
    --subnet-id "$SUBNET_ID" \
    --image-id "$IMAGE_ID" \
    --shape "$SHAPE" \
    --shape-config "{\"ocpus\": $OCPUS, \"memoryInGBs\": $MEMORY_GB}" \
    --display-name "$DISPLAY_NAME" \
    --assign-public-ip true \
    --ssh-authorized-keys-file "$SSH_KEY_PATH" \
    2>&1)

  if echo "$result" | grep -q '"lifecycle-state"'; then
    echo ""
    echo "✅ SUCCESS! Instance created."
    echo "$result"
    # Try to play a sound to alert you (macOS)
    afplay /System/Library/Sounds/Glass.aiff 2>/dev/null
    break
  elif echo "$result" | grep -qi "capacity"; then
    echo "❌ Out of capacity. Retrying in $RETRY_INTERVAL_SECONDS seconds..."
  elif echo "$result" | grep -qi "TooManyRequests"; then
    echo "⚠️  Rate limited. Waiting a bit longer before retry..."
    sleep 120
  else
    echo "⚠️  Unexpected error:"
    echo "$result"
    echo "Retrying anyway in $RETRY_INTERVAL_SECONDS seconds..."
  fi

  attempt=$((attempt+1))
  sleep "$RETRY_INTERVAL_SECONDS"
done
