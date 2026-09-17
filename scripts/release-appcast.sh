#!/usr/bin/env bash
# release-appcast.sh — EdDSA-sign a DMG and merge one item into the
# ring's appcast feed on the gh-pages checkout (ADR-0080 §3).
#
# Usage:
#   scripts/release-appcast.sh --ring stable|nightly --dmg PATH \
#     --version V --build-number N --download-url URL \
#     --notes-file PATH --site-dir DIR
#
# Required environment:
#   BREV_SPARKLE_PRIVATE_ED_KEY_FILE  Path to the Sparkle EdDSA private
#                                   key file (must be mode 0600).
#
# Feed layout inside --site-dir:
#   stable  -> appcast.xml        (full history kept)
#   nightly -> appcast-nightly.xml (newest 14 items kept)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RING=""; DMG=""; VERSION=""; BUILD_NUMBER=""; DOWNLOAD_URL=""; NOTES_FILE=""; SITE_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ring)         RING="${2:?}"; shift 2 ;;
    --dmg)          DMG="${2:?}"; shift 2 ;;
    --version)      VERSION="${2:?}"; shift 2 ;;
    --build-number) BUILD_NUMBER="${2:?}"; shift 2 ;;
    --download-url) DOWNLOAD_URL="${2:?}"; shift 2 ;;
    --notes-file)   NOTES_FILE="${2:?}"; shift 2 ;;
    --site-dir)     SITE_DIR="${2:?}"; shift 2 ;;
    -h|--help)      sed -n '2,20p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "release-appcast.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done

for pair in "ring:$RING" "dmg:$DMG" "version:$VERSION" "build-number:$BUILD_NUMBER" \
            "download-url:$DOWNLOAD_URL" "notes-file:$NOTES_FILE" "site-dir:$SITE_DIR"; do
  [[ -z "${pair#*:}" ]] && { echo "release-appcast.sh: --${pair%%:*} is required" >&2; exit 2; }
done

case "$RING" in
  stable)  FEED_NAME="appcast.xml";         FEED_TITLE="Brev changelog";         MAX_ITEMS=0 ;;
  nightly) FEED_NAME="appcast-nightly.xml"; FEED_TITLE="Brev Nightly changelog"; MAX_ITEMS=14 ;;
  *) echo "release-appcast.sh: --ring must be stable or nightly" >&2; exit 2 ;;
esac

[[ -f "$DMG" ]]        || { echo "release-appcast.sh: missing DMG $DMG" >&2; exit 1; }
[[ -f "$NOTES_FILE" ]] || { echo "release-appcast.sh: missing notes $NOTES_FILE" >&2; exit 1; }

KEY_FILE="${BREV_SPARKLE_PRIVATE_ED_KEY_FILE:-}"
if [[ -z "$KEY_FILE" || ! -f "$KEY_FILE" ]]; then
  echo "release-appcast.sh: BREV_SPARKLE_PRIVATE_ED_KEY_FILE must point to the Sparkle private key file" >&2
  exit 1
fi
KEY_PERMS="$(stat -f '%Lp' "$KEY_FILE")"
if [[ "$KEY_PERMS" != "600" ]]; then
  echo "release-appcast.sh: $KEY_FILE must be mode 0600 (found $KEY_PERMS)" >&2
  exit 1
fi

SIGN_UPDATE="$REPO_ROOT/Tuist/.build/artifacts/sparkle/Sparkle/bin/sign_update"
if [[ ! -x "$SIGN_UPDATE" ]]; then
  SIGN_UPDATE="$(command -v sign_update || true)"
fi
[[ -n "$SIGN_UPDATE" ]] || { echo "release-appcast.sh: sign_update not found" >&2; exit 1; }

# sign_update prints: sparkle:edSignature="<sig>" length="<bytes>"
SIGN_OUTPUT="$("$SIGN_UPDATE" --ed-key-file "$KEY_FILE" "$DMG")"
SIGNATURE="$(printf '%s\n' "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' | head -1)"
if [[ -z "$SIGNATURE" ]]; then
  echo "release-appcast.sh: could not parse EdDSA signature from sign_update output:" >&2
  printf '%s\n' "$SIGN_OUTPUT" >&2
  exit 1
fi

mkdir -p "$SITE_DIR"
python3 "$SCRIPT_DIR/release-appcast-merge.py" \
  --feed "$SITE_DIR/$FEED_NAME" \
  --version "$VERSION" \
  --build-number "$BUILD_NUMBER" \
  --download-url "$DOWNLOAD_URL" \
  --dmg "$DMG" \
  --signature "$SIGNATURE" \
  --notes-file "$NOTES_FILE" \
  --title "$FEED_TITLE" \
  --max-items "$MAX_ITEMS"
