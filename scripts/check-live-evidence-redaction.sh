#!/usr/bin/env bash
# Scan QA evidence files for obvious token/code leaks before sharing.

set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "usage: scripts/check-live-evidence-redaction.sh <file-or-dir> [more paths...]" >&2
  exit 2
fi

failures=0

# High-confidence patterns only (to keep noise low).
set +e
raw_matches="$(
  rg -n -H --color never \
    -e '(access_token|refresh_token|id_token|authorization_code)[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9._~+/\-=]{8,}' \
    -e '\bBearer[[:space:]]+[A-Za-z0-9._~+/\-=]{12,}' \
    -e 'app\.brev://oauth/callback[^[:space:]]*code=' \
    -e 'eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}' \
    "$@" 2>&1
)"
rg_status=$?
set -e

if [[ $rg_status -gt 1 ]]; then
  echo "$raw_matches" >&2
  echo "check-live-evidence-redaction.sh: scan failed" >&2
  exit "$rg_status"
fi

if [[ $rg_status -eq 0 ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # Ignore lines already explicitly redacted.
    if printf '%s\n' "$line" | rg -qi 'redacted|<hidden>|placeholder'; then
      continue
    fi
    printf '%s\n' "$line"
    failures=$((failures + 1))
  done <<<"$raw_matches"
fi

if [[ $failures -ne 0 ]]; then
  echo "check-live-evidence-redaction.sh: $failures potential sensitive line(s) found" >&2
  echo "Redact before attaching evidence." >&2
  exit 1
fi

echo "check-live-evidence-redaction.sh: OK (no obvious token/code leaks)"
