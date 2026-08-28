#!/usr/bin/env bash
# Prepare the generated Tuist workspace and derived package metadata used by Xcode.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OPEN_WORKSPACE=0

usage() {
  cat <<'EOF'
usage: scripts/prepare-xcode-workspace.sh [--open]

Runs the same local generation sequence as CI:
  1. tuist install
  2. tuist generate --no-open

Use this before direct xcodebuild or XcodeBuildMCP builds from a fresh
checkout. Pass --open to open Brev.xcworkspace after generation.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --open)
      OPEN_WORKSPACE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "prepare-xcode-workspace.sh: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

run_with_tools() {
  if command -v mise >/dev/null 2>&1; then
    mise exec -- "$@"
  else
    "$@"
  fi
}

run_tuist() {
  run_with_tools tuist "$@"
}

cd "$ROOT"

echo "==> Resolving Tuist dependencies"
run_tuist install

sparkle_xcframework="$ROOT/Tuist/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework"
if [[ ! -d "$sparkle_xcframework" ]]; then
  echo "prepare-xcode-workspace.sh: Sparkle XCFramework was not prepared at" >&2
  echo "  $sparkle_xcframework" >&2
  echo "Check the Tuist dependency resolution output before running xcodebuild." >&2
  exit 1
fi

echo "==> Generating Brev.xcworkspace"
if [[ "$OPEN_WORKSPACE" == "1" ]]; then
  run_tuist generate
else
  run_tuist generate --no-open
fi

echo "prepare-xcode-workspace.sh: OK"
