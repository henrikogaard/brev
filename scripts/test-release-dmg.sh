#!/usr/bin/env bash
# Exercise both packaging paths with a fake export and real disk images.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/brev-dmg-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/scripts" "$WORK/bin"
cp "$ROOT/scripts/release-dmg.sh" "$ROOT/scripts/release-artifact-verify.sh" "$WORK/scripts/"

cat > "$WORK/bin/xcodebuild" <<'SH'
#!/bin/bash
set -eu
while [[ $# -gt 0 ]]; do
  case "$1" in
    -exportPath) export_dir="$2"; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "$export_dir/$TEST_APP/Contents"
printf '<plist version="1.0"><dict/></plist>\n' > "$export_dir/$TEST_APP/Contents/Info.plist"
touch "$export_dir/DistributionSummary.plist" "$export_dir/ExportOptions.plist" "$export_dir/Packaging.log"
SH
chmod +x "$WORK/bin/xcodebuild"

# Exclude Homebrew's optional create-dmg for the fallback run.
export PATH="$WORK/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export TEST_APP="Brev.app"
bash "$WORK/scripts/release-dmg.sh" --skip-notarize --version 1.2.3
DMG="$WORK/build/release/Brev-1.2.3.dmg"
bash "$WORK/scripts/release-artifact-verify.sh" --dmg-path "$DMG" --skip-gatekeeper --skip-stapler

# Model create-dmg's --app-drop-link behavior, asserting the staging contract.
cat > "$WORK/bin/create-dmg" <<'SH'
#!/bin/bash
set -eu
for arg in "$@"; do
  previous="${last:-}"
  last="$arg"
done
src="$last"
dmg="$previous"
[[ "$(find "$src" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" == 1 ]]
[[ -d "$src/$TEST_APP" ]]
[[ " $* " == *" --app-drop-link 430 180 "* ]]
ln -s /Applications "$src/Applications"
hdiutil create -volname "Brev Nightly Test" -srcfolder "$src" -format UDZO "$dmg"
SH
chmod +x "$WORK/bin/create-dmg"
export TEST_APP="Brev Nightly.app"
bash "$WORK/scripts/release-dmg.sh" --ring nightly --skip-notarize --version 1.2.3-nightly.20261008
bash "$WORK/scripts/release-artifact-verify.sh" \
  --dmg-path "$WORK/build/release/Brev-Nightly-20261008.dmg" --skip-gatekeeper --skip-stapler

# A valid checksum alone must not allow the original broken installer through.
mkdir -p "$WORK/bad/Brev.app/Contents"
printf '<plist version="1.0"><dict/></plist>\n' > "$WORK/bad/Brev.app/Contents/Info.plist"
for defect in missing-shortcut wrong-shortcut export-log; do
  case "$defect" in
    wrong-shortcut) ln -s /tmp "$WORK/bad/Applications" ;;
    export-log)
      rm "$WORK/bad/Applications"
      ln -s /Applications "$WORK/bad/Applications"
      touch "$WORK/bad/Packaging.log"
      ;;
  esac
  hdiutil create -volname "Brev Broken Test" -srcfolder "$WORK/bad" \
    -format UDZO "$WORK/$defect.dmg" >/dev/null
  shasum -a 256 "$WORK/$defect.dmg" > "$WORK/$defect.dmg.sha256"
  if bash "$WORK/scripts/release-artifact-verify.sh" --dmg-path "$WORK/$defect.dmg" \
      --skip-gatekeeper --skip-stapler > "$WORK/$defect.log" 2>&1; then
    echo "ERROR: accepted $defect DMG" >&2
    exit 1
  fi
  grep -Eq 'Unexpected DMG contents|DMG must contain an Applications symlink' "$WORK/$defect.log"
done
echo "test-release-dmg.sh: OK"
