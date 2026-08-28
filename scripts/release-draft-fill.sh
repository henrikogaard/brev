#!/usr/bin/env bash
# release-draft-fill.sh — Fill macOS beta GitHub Release draft metadata from release artifacts.
#
# Usage:
#   scripts/release-draft-fill.sh --version 0.1.0 --dmg-path build/release/BrevMail.dmg
#   scripts/release-draft-fill.sh --version 0.1.0 --output /tmp/release.md

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DRAFT="docs/releases/macos-beta-github-release-draft.md"
VERSION=""
TAG=""
COMMIT=""
DMG_PATH="build/release/BrevMail.dmg"
OUTPUT=""
ASSET_NAME=""

usage() {
  cat <<'EOF'
usage: scripts/release-draft-fill.sh --version VERSION [--tag TAG] [--commit SHA] [--dmg-path PATH] [--output PATH] [--asset-name NAME]

Examples:
  scripts/release-draft-fill.sh --version 0.1.0 --dmg-path build/release/BrevMail.dmg
  scripts/release-draft-fill.sh --version 0.1.0 --output /tmp/brev-release.md
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --tag)
      TAG="${2:-}"
      shift 2
      ;;
    --commit)
      COMMIT="${2:-}"
      shift 2
      ;;
    --dmg-path)
      DMG_PATH="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT="${2:-}"
      shift 2
      ;;
    --asset-name)
      ASSET_NAME="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "release-draft-fill.sh: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  echo "release-draft-fill.sh: --version is required" >&2
  usage >&2
  exit 2
fi

if [[ ! -f "$DRAFT" ]]; then
  echo "release-draft-fill.sh: missing draft at $DRAFT" >&2
  exit 1
fi

if [[ ! -f "$DMG_PATH" ]]; then
  echo "release-draft-fill.sh: missing DMG artifact at $DMG_PATH" >&2
  exit 1
fi

if [[ -z "$TAG" ]]; then
  TAG="v$VERSION"
fi

if [[ -z "$COMMIT" ]]; then
  COMMIT="$(git rev-parse HEAD)"
fi

if [[ -z "$OUTPUT" ]]; then
  OUTPUT="build/release/github-release-${VERSION}.md"
fi

if [[ -z "$ASSET_NAME" ]]; then
  ASSET_NAME="Brev-${VERSION}.dmg"
fi

mkdir -p "$(dirname "$OUTPUT")"

CHECKSUM_PATH="${DMG_PATH}.sha256"
if [[ ! -f "$CHECKSUM_PATH" ]]; then
  shasum -a 256 "$DMG_PATH" >"$CHECKSUM_PATH"
fi

CHECKSUM_LINE="$(awk 'NF {print; exit}' "$CHECKSUM_PATH")"
CHECKSUM_DIGEST="$(awk 'NF {print $1; exit}' "$CHECKSUM_PATH")"
if [[ -z "$CHECKSUM_LINE" || ! "$CHECKSUM_DIGEST" =~ ^[[:xdigit:]]{64}$ ]]; then
  echo "release-draft-fill.sh: checksum file has no digest value: $CHECKSUM_PATH" >&2
  exit 1
fi

if [[ "$ASSET_NAME" == */* || "$ASSET_NAME" != *.dmg ]]; then
  echo "release-draft-fill.sh: --asset-name must be a basename ending in .dmg: $ASSET_NAME" >&2
  exit 1
fi

export VERSION TAG COMMIT DMG_PATH ASSET_NAME CHECKSUM_DIGEST

perl -0pe '
  s/`v<version>`/`$ENV{TAG}`/g;
  s/Brev <version>/Brev $ENV{VERSION}/g;
  s/<version>/$ENV{VERSION}/g;
  s/<release commit sha>/$ENV{COMMIT}/g;
  s/DMG asset: `[^`]+`/DMG asset: `$ENV{ASSET_NAME}`/;
  s/SHA-256: `<paste shasum -a 256 build\/release\/BrevMail\.dmg output>`/SHA-256: `$ENV{CHECKSUM_DIGEST}`/;
  s/shasum -a 256 build\/release\/BrevMail\.dmg/shasum -a 256 $ENV{DMG_PATH}/g;
  s/build\/release\/BrevMail\.dmg/$ENV{DMG_PATH}/g;
' "$DRAFT" >"$OUTPUT"

if ! rg -Fq "DMG asset: \`$ASSET_NAME\`" "$OUTPUT"; then
  echo "release-draft-fill.sh: output draft does not contain the requested DMG asset name: $ASSET_NAME" >&2
  exit 1
fi
if ! rg -Fq "SHA-256: \`$CHECKSUM_DIGEST\`" "$OUTPUT"; then
  echo "release-draft-fill.sh: output draft does not contain the artifact checksum $CHECKSUM_DIGEST" >&2
  exit 1
fi

echo "release-draft-fill.sh: wrote $OUTPUT"
echo "release-draft-fill.sh: checksum source $CHECKSUM_PATH ($CHECKSUM_DIGEST)"
