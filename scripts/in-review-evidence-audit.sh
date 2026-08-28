#!/usr/bin/env bash
# in-review-evidence-audit.sh — Audit in-review evidence records for closure readiness.
#
# Usage:
#   scripts/in-review-evidence-audit.sh [--date YYYY-MM-DD] [--output <path>]
#
# The audit flags unresolved markers in evidence docs:
#   TODO, PENDING, BLOCKED

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

run_date="$(date +%F)"
output=""
strict=0
max_lines=10

usage() {
  cat <<'EOF'
usage: scripts/in-review-evidence-audit.sh [--date YYYY-MM-DD] [--output <path>] [--strict] [--max-lines N]

Examples:
  scripts/in-review-evidence-audit.sh
  scripts/in-review-evidence-audit.sh --date 2026-06-01
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
      echo "in-review-evidence-audit.sh: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! [[ "$max_lines" =~ ^[0-9]+$ ]] || [[ "$max_lines" -lt 1 ]]; then
  echo "in-review-evidence-audit.sh: --max-lines must be a positive integer" >&2
  exit 2
fi

if [[ -z "$output" ]]; then
  output="docs/qa/results/in-review-evidence-audit-${run_date}.md"
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
total_todo=0
total_pending=0
total_blocked=0
detail_sections=""

{
  echo "# In-review Evidence Audit"
  echo
  echo "**Date:** ${run_date}  "
  echo "**Operator:** Codex  "
  echo
  echo "## Record Status"
  echo
  echo "| Issue | Evidence record | Unresolved markers | Status |"
  echo "|---|---|---:|---|"

  for entry in "${records[@]}"; do
    issue="${entry%%:*}"
    path="${entry#*:}"
    unresolved=0
    todo_count=0
    pending_count=0
    blocked_count=0
    status="READY"

    if [[ ! -f "$path" ]]; then
      status="MISSING"
      unresolved=1
      total_unresolved=$((total_unresolved + unresolved))
      echo "| #${issue} | \`${path}\` | ${unresolved} | ${status} |"
      continue
    fi

    marker_lines="$(rg -n --pcre2 '\b(TODO|PENDING|BLOCKED)\b' "$path" || true)"
    unresolved="$(
      printf '%s\n' "$marker_lines" \
        | sed '/^$/d' \
        | wc -l \
        | tr -d ' '
    )"

    if [[ "$unresolved" -gt 0 ]]; then
      todo_count="$(printf '%s\n' "$marker_lines" | awk '{c += gsub(/TODO/, "&")} END {print c + 0}')"
      pending_count="$(printf '%s\n' "$marker_lines" | awk '{c += gsub(/PENDING/, "&")} END {print c + 0}')"
      blocked_count="$(printf '%s\n' "$marker_lines" | awk '{c += gsub(/BLOCKED/, "&")} END {print c + 0}')"
    fi

    if [[ "$unresolved" -gt 0 ]]; then
      status="INCOMPLETE"
    fi

    total_unresolved=$((total_unresolved + unresolved))
    total_todo=$((total_todo + todo_count))
    total_pending=$((total_pending + pending_count))
    total_blocked=$((total_blocked + blocked_count))
    echo "| #${issue} | \`${path}\` | ${unresolved} | ${status} |"

    if [[ "$unresolved" -gt 0 ]]; then
      detail_sections+=$'\n'"### #${issue}"$'\n\n'
      detail_sections+="\`${path}\`"$'\n\n'
      detail_sections+="Marker counts: TODO=${todo_count}, PENDING=${pending_count}, BLOCKED=${blocked_count}"$'\n\n'
      detail_sections+="| Line | Marker | Context |"$'\n'
      detail_sections+="|---:|---|---|"$'\n'
      detail_rows=0
      while IFS= read -r match_line; do
        [[ -z "$match_line" ]] && continue
        line_number="${match_line%%:*}"
        context="${match_line#*:}"
        marker="$(
          printf '%s\n' "$context" \
            | rg -o --no-line-number 'TODO|PENDING|BLOCKED' \
            | head -n 1
        )"
        escaped_context="$(printf '%s' "$context" | sed 's/|/\\|/g')"
        detail_sections+="| ${line_number} | ${marker} | ${escaped_context} |"$'\n'
        detail_rows=$((detail_rows + 1))
        if [[ "$detail_rows" -ge "$max_lines" ]]; then
          break
        fi
      done <<< "$marker_lines"
      if [[ "$unresolved" -gt "$max_lines" ]]; then
        remaining=$((unresolved - max_lines))
        detail_sections+=$'\n'"- ...and ${remaining} additional unresolved marker(s)."$'\n'
      fi
    fi
  done

  echo
  echo "## Summary"
  echo
  if [[ $total_unresolved -eq 0 ]]; then
    echo "- All audited in-review evidence records are closure-ready (no unresolved markers)."
  else
    echo "- Total unresolved markers across audited records: **${total_unresolved}**."
    echo "- Marker breakdown: TODO=${total_todo}, PENDING=${total_pending}, BLOCKED=${total_blocked}."
    echo "- Closure remains blocked until unresolved markers are replaced with validated evidence."
  fi

  if [[ -n "$detail_sections" ]]; then
    echo
    echo "## Unresolved Details"
    echo
    printf '%s\n' "$detail_sections"
  fi
} > "$output"

echo "in-review-evidence-audit.sh: wrote $output"

if [[ $strict -eq 1 && $total_unresolved -ne 0 ]]; then
  echo "in-review-evidence-audit.sh: strict mode failed (${total_unresolved} unresolved marker(s))" >&2
  exit 1
fi
