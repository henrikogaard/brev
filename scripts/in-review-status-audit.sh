#!/usr/bin/env bash
# in-review-status-audit.sh — Audit in-review evidence records for unresolved table statuses.
#
# Usage:
#   scripts/in-review-status-audit.sh [--date YYYY-MM-DD] [--output <path>] [--strict] [--max-lines N]
#
# The audit scans markdown table rows for unresolved status values:
#   BLOCKED, PENDING, OPEN, FAIL, PARTIAL

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

run_date="$(date +%F)"
output=""
strict=0
max_lines=10

usage() {
  cat <<'EOF'
usage: scripts/in-review-status-audit.sh [--date YYYY-MM-DD] [--output <path>] [--strict] [--max-lines N]

Examples:
  scripts/in-review-status-audit.sh
  scripts/in-review-status-audit.sh --date 2026-06-01 --strict
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --date)
      run_date="${2:-}"
      shift 2
      ;;
    --output)
      output="${2:-}"
      shift 2
      ;;
    --strict)
      strict=1
      shift
      ;;
    --max-lines)
      max_lines="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "in-review-status-audit.sh: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! [[ "$max_lines" =~ ^[0-9]+$ ]] || [[ "$max_lines" -lt 1 ]]; then
  echo "in-review-status-audit.sh: --max-lines must be a positive integer" >&2
  exit 2
fi

if [[ -z "$output" ]]; then
  output="docs/qa/results/in-review-status-audit-${run_date}.md"
fi

mkdir -p "$(dirname "$output")"

records=(
  "6:docs/qa/results/issue-6-verification-${run_date}.md"
  "96:docs/qa/results/issue-96-verification-${run_date}.md"
  "97:docs/qa/results/issue-97-verification-${run_date}.md"
  "98:docs/qa/results/issue-98-verification-${run_date}.md"
  "99:docs/qa/results/issue-99-verification-${run_date}.md"
  "124:docs/qa/results/issue-124-verification-${run_date}.md"
  "130:docs/qa/results/issue-130-verification-${run_date}.md"
)

total_unresolved=0
total_blocked=0
total_pending=0
total_open=0
total_fail=0
total_partial=0
detail_sections=""

{
  echo "# In-review Status Audit"
  echo
  echo "**Date:** ${run_date}  "
  echo "**Operator:** Codex  "
  echo
  echo "## Record Status"
  echo
  echo "| Issue | Evidence record | Unresolved status rows | Status |"
  echo "|---|---|---:|---|"

  for entry in "${records[@]}"; do
    issue="${entry%%:*}"
    path="${entry#*:}"
    unresolved=0
    blocked_count=0
    pending_count=0
    open_count=0
    fail_count=0
    partial_count=0
    status="READY"

    if [[ ! -f "$path" ]]; then
      status="MISSING"
      unresolved=1
      total_unresolved=$((total_unresolved + unresolved))
      echo "| #${issue} | \`${path}\` | ${unresolved} | ${status} |"
      continue
    fi

    status_lines="$(rg -n --pcre2 '\|.*\b(BLOCKED|PENDING|OPEN|FAIL|PARTIAL)\b.*\|' "$path" || true)"
    unresolved="$(
      printf '%s\n' "$status_lines" \
        | sed '/^$/d' \
        | wc -l \
        | tr -d ' '
    )"

    if [[ "$unresolved" -gt 0 ]]; then
      blocked_count="$(printf '%s\n' "$status_lines" | awk '{c += gsub(/BLOCKED/, "&")} END {print c + 0}')"
      pending_count="$(printf '%s\n' "$status_lines" | awk '{c += gsub(/PENDING/, "&")} END {print c + 0}')"
      open_count="$(printf '%s\n' "$status_lines" | awk '{c += gsub(/\bOPEN\b/, "&")} END {print c + 0}')"
      fail_count="$(printf '%s\n' "$status_lines" | awk '{c += gsub(/\bFAIL\b/, "&")} END {print c + 0}')"
      partial_count="$(printf '%s\n' "$status_lines" | awk '{c += gsub(/PARTIAL/, "&")} END {print c + 0}')"
      status="INCOMPLETE"
    fi

    total_unresolved=$((total_unresolved + unresolved))
    total_blocked=$((total_blocked + blocked_count))
    total_pending=$((total_pending + pending_count))
    total_open=$((total_open + open_count))
    total_fail=$((total_fail + fail_count))
    total_partial=$((total_partial + partial_count))

    echo "| #${issue} | \`${path}\` | ${unresolved} | ${status} |"

    if [[ "$unresolved" -gt 0 ]]; then
      detail_sections+=$'\n'"### #${issue}"$'\n\n'
      detail_sections+="\`${path}\`"$'\n\n'
      detail_sections+="Status counts: BLOCKED=${blocked_count}, PENDING=${pending_count}, OPEN=${open_count}, FAIL=${fail_count}, PARTIAL=${partial_count}"$'\n\n'
      detail_sections+="| Line | Status | Context |"$'\n'
      detail_sections+="|---:|---|---|"$'\n'
      detail_rows=0
      while IFS= read -r match_line; do
        [[ -z "$match_line" ]] && continue
        line_number="${match_line%%:*}"
        context="${match_line#*:}"
        status_token="$(
          printf '%s\n' "$context" \
            | rg -o --no-line-number 'BLOCKED|PENDING|OPEN|FAIL|PARTIAL' \
            | head -n 1
        )"
        escaped_context="$(printf '%s' "$context" | sed 's/|/\\|/g')"
        detail_sections+="| ${line_number} | ${status_token} | ${escaped_context} |"$'\n'
        detail_rows=$((detail_rows + 1))
        if [[ "$detail_rows" -ge "$max_lines" ]]; then
          break
        fi
      done <<< "$status_lines"
      if [[ "$unresolved" -gt "$max_lines" ]]; then
        remaining=$((unresolved - max_lines))
        detail_sections+=$'\n'"- ...and ${remaining} additional unresolved row(s)."$'\n'
      fi
    fi
  done

  echo
  echo "## Summary"
  echo
  if [[ $total_unresolved -eq 0 ]]; then
    echo "- All audited in-review evidence records are status-ready (no unresolved status rows)."
  else
    echo "- Total unresolved status rows across audited records: **${total_unresolved}**."
    echo "- Status breakdown: BLOCKED=${total_blocked}, PENDING=${total_pending}, OPEN=${total_open}, FAIL=${total_fail}, PARTIAL=${total_partial}."
    echo "- Closure remains blocked until unresolved status rows are replaced with validated completion statuses."
  fi

  if [[ -n "$detail_sections" ]]; then
    echo
    echo "## Unresolved Details"
    echo
    printf '%s\n' "$detail_sections"
  fi
} > "$output"

echo "in-review-status-audit.sh: wrote $output"

if [[ $strict -eq 1 && $total_unresolved -ne 0 ]]; then
  echo "in-review-status-audit.sh: strict mode failed (${total_unresolved} unresolved row(s))" >&2
  exit 1
fi
