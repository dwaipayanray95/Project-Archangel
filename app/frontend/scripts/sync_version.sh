#!/bin/bash
# Reads the FRONTEND line out of the repo root's VERSION file and syncs
# it into the two places the frontend actually needs a version string:
# pubspec.yaml's own `version:` field (what Flutter itself uses for
# versionName/CFBundleShortVersionString/file version on every
# platform) and AppVersion's fallback constant (what the app shows
# itself, in Settings etc.).
#
# Run this after editing VERSION, before building - CI runs it too
# (see .github/workflows/build-app.yml) so a build always matches
# whatever FRONTEND currently says, without hand-editing two files
# every time.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_VERSION_FILE="$FRONTEND_DIR/../../VERSION"

FRONTEND_VERSION=$(awk '/^FRONTEND/ {print $2}' "$ROOT_VERSION_FILE")
if [[ -z "$FRONTEND_VERSION" ]]; then
  echo "ERROR: no FRONTEND line found in $ROOT_VERSION_FILE" >&2
  exit 1
fi

ARCHANGEL_VERSION=$(awk '/^ARCHANGEL/ {print $2}' "$ROOT_VERSION_FILE")
if [[ -z "$ARCHANGEL_VERSION" ]]; then
  echo "ERROR: no ARCHANGEL line found in $ROOT_VERSION_FILE" >&2
  exit 1
fi

PUBSPEC="$FRONTEND_DIR/pubspec.yaml"
# Preserve whatever build-number suffix (+N) is already there.
BUILD_NUMBER=$(grep -E '^version: ' "$PUBSPEC" | sed -E 's/^version: [0-9.]+\+?//')
sed -i.bak -E "s/^version: .*/version: ${FRONTEND_VERSION}+${BUILD_NUMBER:-1}/" "$PUBSPEC"
rm -f "$PUBSPEC.bak"

APP_VERSION_DART="$FRONTEND_DIR/lib/services/app_version.dart"
sed -i.bak -E "s/static const String archangel = '[0-9.]+';/static const String archangel = '${ARCHANGEL_VERSION}';/" "$APP_VERSION_DART"
rm -f "$APP_VERSION_DART.bak"

echo "Synced frontend version to $FRONTEND_VERSION, project version to $ARCHANGEL_VERSION (pubspec.yaml, app_version.dart)"
