#!/usr/bin/env bash
# scripts/check-adr-required.sh — enforces ADR-0005 protected-path gate.
#
# If any changed file in the current commit / PR touches a protected path,
# the same commit / PR must add or update a file in ADRs/. The override
# label "adr-not-required" disables this in CI; locally, set
# BREV_SKIP_ADR_CHECK=1.
#
# Modes:
#   - In a Git work tree, with no args: inspects staged + unstaged diff
#     vs. HEAD (matches what `git commit` is about to record).
#   - In CI: pass the base ref as $1 (e.g. origin/main). Compares HEAD vs
#     that ref.
#
# Protected paths come straight from ADR-0005.

set -euo pipefail

BASE="${1:-}"

if [[ -n "$BASE" ]]; then
  CHANGED="$(git diff --name-only "$BASE"...HEAD || true)"
else
  CHANGED="$(
    {
      git diff --cached --name-only
      git diff --name-only
    } | sort -u
  )"
fi
if [[ -z "$CHANGED" ]]; then
  exit 0
fi

# Protected paths — see ADR-0005 §Protected paths.
PROTECTED_RE='^(apps/macOS/Project\.swift$|apps/iOS/Project\.swift$|Workspace\.swift$|\.swiftlint\.yml$|\.swiftformat$|\.mise\.toml$|LICENSE$|NOTICE$|THIRD_PARTY_LICENSES\.md$|packages/(BrevDesign|BrevThemes|BrevAvatars|BrevCalendar|BrevAI)/Sources/.*\.swift$)'

TOUCHED_PROTECTED="$(echo "$CHANGED" | grep -E "$PROTECTED_RE" || true)"
if [[ -z "$TOUCHED_PROTECTED" ]]; then
  exit 0
fi

ADR_TOUCHED="$(echo "$CHANGED" | grep -E '^ADRs/.*\.md$' || true)"
if [[ -n "$ADR_TOUCHED" ]]; then
  exit 0
fi

cat >&2 <<EOF
check-adr-required: protected paths changed without an ADR update.

Protected files touched:
$(echo "$TOUCHED_PROTECTED" | sed 's/^/  - /')

Add or update an ADR in ADRs/ (use prompts/new-adr.md as a starter), or set
the GitHub label "adr-not-required" on the PR if this is a genuine emergency.
Locally bypass with: BREV_SKIP_ADR_CHECK=1 git commit ...
EOF
exit 1
