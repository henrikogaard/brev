#!/usr/bin/env bash
# Keep Tuist and generated app projects on the App Store Connect team.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

expected_team="45AD7E7G5G"
constants="Tuist/ProjectDescriptionHelpers/BrevConstants.swift"

if ! grep -q "teamID = \"${expected_team}\"" "$constants"; then
  echo "ERROR: $constants is not configured for Apple team ${expected_team}" >&2
  exit 1
fi

for project in \
  apps/iOS/BrevIOS.xcodeproj/project.pbxproj \
  apps/macOS/BrevMacOS.xcodeproj/project.pbxproj; do
  if ! grep -q "DEVELOPMENT_TEAM = ${expected_team};" "$project"; then
    echo "ERROR: $project is not generated for Apple team ${expected_team}" >&2
    exit 1
  fi
done

echo "test-apple-team-config.sh: OK"
