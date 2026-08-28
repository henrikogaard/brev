#!/usr/bin/env bash
# release-artifact-verify.sh — Verify release DMG artifact integrity/readiness.
#
# Usage:
#   scripts/release-artifact-verify.sh [--dmg-path <path>] [--checksum-path <path>] [--skip-gatekeeper] [--skip-stapler]
#
# Defaults:
#   dmg path: build/release/BrevMail.dmg
#   checksum path: <dmg-path>.sha256

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DMG_PATH="$ROOT/build/release/BrevMail.dmg"
CHECKSUM_PATH=""
SKIP_GATEKEEPER=0
SKIP_STAPLER=0

usage() {
  cat <<'EOF'
usage: scripts/release-artifact-verify.sh [--dmg-path <path>] [--checksum-path <path>] [--skip-gatekeeper] [--skip-stapler]

Examples:
  scripts/release-artifact-verify.sh
  scripts/release-artifact-verify.sh --dmg-path build/release/BrevMail.dmg
  scripts/release-artifact-verify.sh --skip-gatekeeper --skip-stapler
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dmg-path)
      DMG_PATH="${2:-}"
      shift 2
      ;;
    --checksum-path)
      CHECKSUM_PATH="${2:-}"
      shift 2
      ;;
    --skip-gatekeeper)
      SKIP_GATEKEEPER=1
      shift
      ;;
    --skip-stapler)
      SKIP_STAPLER=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "release-artifact-verify.sh: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$CHECKSUM_PATH" ]]; then
  CHECKSUM_PATH="${DMG_PATH}.sha256"
fi

if [[ ! -f "$DMG_PATH" ]]; then
  echo "release-artifact-verify.sh: missing DMG artifact at $DMG_PATH" >&2
  exit 1
fi

if [[ ! -f "$CHECKSUM_PATH" ]]; then
  echo "release-artifact-verify.sh: missing checksum artifact at $CHECKSUM_PATH" >&2
  exit 1
fi

echo "==> artifact presence"
echo "    DMG:      $DMG_PATH"
echo "    Checksum: $CHECKSUM_PATH"

echo "==> checksum validation"
expected="$(awk '{print $1}' "$CHECKSUM_PATH")"
actual="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
if [[ -z "$expected" ]]; then
  echo "release-artifact-verify.sh: checksum file has no digest value" >&2
  exit 1
fi
if [[ "$expected" != "$actual" ]]; then
  echo "release-artifact-verify.sh: checksum mismatch" >&2
  echo "  expected: $expected" >&2
  echo "  actual:   $actual" >&2
  exit 1
fi
echo "    OK"

if [[ $SKIP_STAPLER -eq 0 ]]; then
  echo "==> stapler validation"
  xcrun stapler validate "$DMG_PATH"
  echo "    OK"
else
  echo "==> stapler validation"
  echo "    SKIP: --skip-stapler"
fi

if [[ $SKIP_GATEKEEPER -eq 0 ]]; then
  echo "==> gatekeeper assessment"
  spctl -a -t open --context context:primary-signature -v "$DMG_PATH"
  echo "    OK"
else
  echo "==> gatekeeper assessment"
  echo "    SKIP: --skip-gatekeeper"
fi

echo "release-artifact-verify.sh: OK"
