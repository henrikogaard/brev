#!/usr/bin/env bash
# release-dmg.sh — Export, package, notarize, and staple the macOS release DMG.
#
# Usage:
#   scripts/release-dmg.sh [--dry-run] [--skip-notarize]
#
# Required environment variables:
#   BREV_SIGNING_IDENTITY   Developer ID Application certificate
#   BREV_TEAM_ID            Apple Developer team ID
#   BREV_ASC_KEY_ID         App Store Connect API key ID
#   BREV_ASC_ISSUER_ID      App Store Connect API issuer ID
#   BREV_ASC_KEY_PATH       Path to the .p8 private key file
#
# Input:
#   build/release/BrevMail.xcarchive   (produced by release-archive.sh)
#
# Output:
#   build/release/BrevMail.dmg
#   build/release/BrevMail.dmg.sha256
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DRY_RUN=false; SKIP_NOTARIZE=false
for arg in "$@"; do
  [[ "$arg" == "--dry-run" ]]        && DRY_RUN=true
  [[ "$arg" == "--skip-notarize" ]]  && SKIP_NOTARIZE=true
done

ENV_FILE="$REPO_ROOT/.env.local"
[[ -f "$ENV_FILE" ]] && { set -a; source "$ENV_FILE"; set +a; }

# ── Validate ──────────────────────────────────────────────────────────────────
ARCHIVE_PATH="$REPO_ROOT/build/release/BrevMail.xcarchive"
EXPORT_DIR="$REPO_ROOT/build/release/export"
APP_PATH="$EXPORT_DIR/Brev.app"
DMG_PATH="$REPO_ROOT/build/release/BrevMail.dmg"
EXPORT_OPTIONS="$REPO_ROOT/scripts/export-options-developer-id.plist"

required_for_notarize=("BREV_SIGNING_IDENTITY" "BREV_ASC_KEY_ID" "BREV_ASC_ISSUER_ID" "BREV_ASC_KEY_PATH")
if [[ "$SKIP_NOTARIZE" == "false" ]]; then
  missing=()
  for var in "${required_for_notarize[@]}"; do
    [[ -z "${!var:-}" ]] && missing+=("$var")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing notarization variables:"
    for var in "${missing[@]}"; do echo "  $var"; done
    echo "Use --skip-notarize to skip, or set them in .env.local."
    exit 1
  fi
fi

echo "=== Brev macOS Release DMG ==="
[[ "$DRY_RUN" == "true" ]] && echo "(DRY RUN)" && exit 0

# Packaging is rerunnable: remove only the previous release outputs that this
# invocation owns, including a stale checksum that could otherwise be
# mistaken for the newly-created image.
mkdir -p "$(dirname "$DMG_PATH")"
rm -rf "$EXPORT_DIR"
rm -f "$DMG_PATH" "$DMG_PATH.sha256"

# 1. xcodebuild -exportArchive
echo "→ Exporting archive…"
if ! xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS"; then
  # Local validation fallback: allow dev-signed archive app extraction when
  # notarization is explicitly skipped.
  if [[ "$SKIP_NOTARIZE" == "true" ]]; then
    ARCHIVE_APP="$ARCHIVE_PATH/Products/Applications/Brev.app"
    if [[ ! -d "$ARCHIVE_APP" ]]; then
      echo "ERROR: export failed and archive app is missing at $ARCHIVE_APP" >&2
      exit 1
    fi
    echo "  WARN: exportArchive failed; using archive app bundle directly because --skip-notarize is set" >&2
    rm -rf "$EXPORT_DIR"
    mkdir -p "$EXPORT_DIR"
    cp -R "$ARCHIVE_APP" "$APP_PATH"
  else
    exit 1
  fi
fi

if [[ ! -d "$APP_PATH" && -d "$EXPORT_DIR/BrevMail.app" ]]; then
  APP_PATH="$EXPORT_DIR/BrevMail.app"
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: exported app bundle not found at $EXPORT_DIR/Brev.app or $EXPORT_DIR/BrevMail.app" >&2
  exit 1
fi

APP_BUNDLE_NAME="$(basename "$APP_PATH")"

# 2. Create DMG with create-dmg (brew install create-dmg)
echo "→ Creating DMG…"
if command -v create-dmg >/dev/null 2>&1; then
  create-dmg \
    --volname "Brev" \
    --volicon "$APP_PATH/Contents/Resources/AppIcon.icns" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 128 \
    --icon "$APP_BUNDLE_NAME" 160 180 \
    --hide-extension "$APP_BUNDLE_NAME" \
    --app-drop-link 430 180 \
    "$DMG_PATH" \
    "$EXPORT_DIR/"
else
  echo "  WARN: create-dmg not found; using hdiutil fallback packaging" >&2
  hdiutil create \
    -volname "Brev" \
    -srcfolder "$EXPORT_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"
fi

if [[ "$SKIP_NOTARIZE" == "false" ]]; then
  # 3. Sign the disk image so Gatekeeper can validate the downloaded
  # container itself, not only the app bundle inside it.
  echo "→ Signing DMG…"
  codesign --force --sign "$BREV_SIGNING_IDENTITY" --timestamp "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"

  # 4. Notarize
  echo "→ Submitting DMG for notarization…"
  xcrun notarytool submit "$DMG_PATH" \
    --key "$BREV_ASC_KEY_PATH" \
    --key-id "$BREV_ASC_KEY_ID" \
    --issuer "$BREV_ASC_ISSUER_ID" \
    --wait

  # 5. Staple
  echo "→ Stapling notarization ticket…"
  xcrun stapler staple "$DMG_PATH"

  # 6. Verify Gatekeeper
  echo "→ Verifying Gatekeeper…"
  spctl -a -t open --context context:primary-signature -v "$DMG_PATH"
fi

# 7. Checksum
echo "→ Generating SHA-256 checksum…"
shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"
cat "$DMG_PATH.sha256"

echo ""
echo "DMG ready: $DMG_PATH"
echo "Checksum:  $DMG_PATH.sha256"
echo "Next: scripts/release-smoke.sh --installed"
