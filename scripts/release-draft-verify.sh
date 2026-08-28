#!/usr/bin/env bash
# release-draft-verify.sh — Validate release-note draft readiness for #99.
#
# This script verifies:
# - expected sections exist
# - only approved placeholders remain
# - known issues are linked to focused GitHub issues
# - no obvious secret material appears in the draft

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DRAFT="docs/releases/macos-beta-github-release-draft.md"
DMG_PATH=""
VERSION=""
ASSET_NAME=""
errors=0

usage() {
  cat <<'EOF'
usage: scripts/release-draft-verify.sh [--draft PATH] [--dmg-path PATH] [--version VERSION] [--asset-name NAME]

Examples:
  scripts/release-draft-verify.sh
  scripts/release-draft-verify.sh --draft build/release/github-release-0.1.0.md
  scripts/release-draft-verify.sh --draft build/release/github-release-0.1.0.md \
    --dmg-path build/release/BrevMail.dmg --version 0.1.0
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --draft)
      DRAFT="${2:-}"
      shift 2
      ;;
    --dmg-path)
      DMG_PATH="${2:-}"
      shift 2
      ;;
    --version)
      VERSION="${2:-}"
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
      echo "release-draft-verify.sh: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

ok() {
  echo "    OK: $1"
}

fail() {
  echo " ERROR: $1" >&2
  errors=$((errors + 1))
}

check_pattern() {
  local description="$1"
  local pattern="$2"
  if rg -q "$pattern" "$DRAFT"; then
    ok "$description"
  else
    fail "$description"
  fi
}

check_artifact_metadata() {
  if [[ -z "$DMG_PATH" && -z "$VERSION" && -z "$ASSET_NAME" ]]; then
    return
  fi

  if [[ -z "$DMG_PATH" || ! -f "$DMG_PATH" ]]; then
    fail "Artifact cross-check requires an existing --dmg-path"
    return
  fi

  local digest expected_asset
  digest="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
  expected_asset="$ASSET_NAME"
  if [[ -z "$expected_asset" && -n "$VERSION" ]]; then
    expected_asset="Brev-${VERSION}.dmg"
  fi

  if [[ -n "$expected_asset" ]] && ! rg -Fq "DMG asset: \`$expected_asset\`" "$DRAFT"; then
    fail "Filled draft asset name does not match $expected_asset"
  else
    ok "Filled draft asset name matches artifact metadata"
  fi

  if rg -Fq "SHA-256: \`$digest\`" "$DRAFT"; then
    ok "Filled draft checksum matches $(basename "$DMG_PATH")"
  else
    fail "Filled draft checksum does not match $DMG_PATH ($digest)"
  fi
}

echo "==> release draft presence"
[[ -f "$DRAFT" ]] && ok "$DRAFT present" || fail "$DRAFT missing"

echo "==> required sections"
check_pattern "Release metadata section present" '^## Release Metadata$'
check_pattern "Highlights section present" '^## Highlights$'
check_pattern "Installation notes section present" '^## Installation Notes$'
check_pattern "Known issues section present" '^## Known Issues And Beta Limits$'
check_pattern "Privacy/network section present" '^## Privacy And Network Surfaces$'
check_pattern "Verification checklist section present" '^## Verification Before Publishing$'

echo "==> focused known-issue links"
if [[ $(rg -o '#[0-9]+' "$DRAFT" | sort -u | wc -l | tr -d ' ') -ge 3 ]]; then
  ok "Known-issues section links focused GitHub issues"
else
  fail "Known-issues section should link at least three focused GitHub issues"
fi

echo "==> gatekeeper/install expectations"
check_pattern "Gatekeeper expectations documented" 'Gatekeeper'
check_pattern "Checksum verification command included" 'shasum -a 256'

echo "==> placeholder audit"
tmp_all="$(mktemp)"
tmp_allowed="$(mktemp)"
trap 'rm -f "$tmp_all" "$tmp_allowed"' EXIT

rg -o '<[^>]+>' "$DRAFT" | sort -u > "$tmp_all" || true
cat > "$tmp_allowed" <<'EOF'
<pass/fail, date>
<paste shasum -a 256 build/release/BrevMail.dmg output>
<release commit sha>
<version>
EOF

if comm -23 "$tmp_all" "$tmp_allowed" | rg . >/dev/null 2>&1; then
  fail "Draft contains unapproved placeholders"
  comm -23 "$tmp_all" "$tmp_allowed" >&2
else
  ok "Only approved placeholders remain"
fi

echo "==> obvious secret-pattern scan"
if rg -n -i 'BEGIN (RSA|EC|OPENSSH) PRIVATE KEY|BREV_ASC_KEY|APP_STORE_CONNECT|SPARKLE_PRIVATE_KEY|BEARER|TOKEN=' "$DRAFT" >/dev/null 2>&1; then
  fail "Draft appears to include sensitive credential markers"
else
  ok "No obvious secret markers in release draft"
fi

echo "==> artifact metadata cross-check"
check_artifact_metadata

if [[ $errors -ne 0 ]]; then
  echo "release-draft-verify.sh: ${errors} check(s) failed" >&2
  exit 1
fi

echo "release-draft-verify.sh: OK"
