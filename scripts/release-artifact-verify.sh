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

echo "==> mounted installer contents"
MOUNT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/brev-dmg-verify.XXXXXX")"
cleanup() {
  hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
  rmdir "$MOUNT_DIR" 2>/dev/null || true
}
trap cleanup EXIT
hdiutil attach "$DMG_PATH" -readonly -nobrowse -mountpoint "$MOUNT_DIR" >/dev/null
python3 - "$MOUNT_DIR" <<'PY'
import os
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
visible = {item.name for item in root.iterdir() if not item.name.startswith(".")}
apps = visible & {"Brev.app", "Brev Nightly.app", "BrevMail.app"}
if len(apps) != 1 or visible != apps | {"Applications"}:
    sys.exit(f"Unexpected DMG contents: {sorted(visible)}; expected one Brev app and Applications")
app = root / next(iter(apps))
if not app.is_dir() or app.is_symlink() or not (app / "Contents/Info.plist").is_file():
    sys.exit("Missing app bundle in DMG")
link = root / "Applications"
if not link.is_symlink() or os.readlink(link) != "/Applications":
    sys.exit("DMG must contain an Applications symlink pointing to /Applications")
print("    OK: app bundle and Applications shortcut; no export logs/plists")
PY
hdiutil detach "$MOUNT_DIR" >/dev/null
rmdir "$MOUNT_DIR"
trap - EXIT

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
