#!/usr/bin/env bash
# release-machine-closeout.sh — End-to-end release-machine evidence run for in-review release issues.
#
# Usage:
#   scripts/release-machine-closeout.sh [--date YYYY-MM-DD] [--output-dir <dir>] [--app-path <path>] [--dry-run]
#
# Produces:
# - command transcripts under <output-dir>/logs/
# - markdown summary at <output-dir>/release-machine-closeout-summary.md
#
# Designed for release-machine execution to gather closure evidence for:
# - #96 clean-checkout archive
# - #97 DMG + notarization + Gatekeeper
# - #98 installed app verification
# - #99 release-note checksum/final verification fill-in
# - #6 umbrella packaging closure

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

run_date="$(date +%F)"
output_dir=""
app_path=""
dry_run=0

usage() {
  cat <<'EOF'
usage: scripts/release-machine-closeout.sh [--date YYYY-MM-DD] [--output-dir <dir>] [--app-path <path>] [--dry-run]

Examples:
  scripts/release-machine-closeout.sh --app-path /Applications/Brev.app
  scripts/release-machine-closeout.sh --date 2026-06-01 --output-dir docs/qa/results/release-machine-2026-06-01
  scripts/release-machine-closeout.sh --dry-run
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --date)
      run_date="${2:-}"
      shift 2
      ;;
    --output-dir)
      output_dir="${2:-}"
      shift 2
      ;;
    --app-path)
      app_path="${2:-}"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "release-machine-closeout.sh: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$output_dir" ]]; then
  output_dir="$ROOT/docs/qa/results/release-machine-${run_date}"
fi

logs_dir="$output_dir/logs"
summary_path="$output_dir/release-machine-closeout-summary.md"

commit_sha="$(git rev-parse --verify HEAD 2>/dev/null || echo "unknown")"
commit_subject="$(git log -1 --pretty=%s 2>/dev/null || echo "unknown")"
if git diff --quiet 2>/dev/null &&
  git diff --cached --quiet 2>/dev/null &&
  [[ -z "$(git ls-files --others --exclude-standard 2>/dev/null)" ]]; then
  pre_run_worktree="clean"
else
  pre_run_worktree="dirty"
fi

mkdir -p "$logs_dir"

if [[ -z "$app_path" ]]; then
  if [[ -d /Applications/Brev.app ]]; then
    app_path="/Applications/Brev.app"
  elif [[ -d /Applications/BrevMail.app ]]; then
    app_path="/Applications/BrevMail.app"
  fi
fi

declare -a steps=(
  "preflight_strict|scripts/release-preflight.sh --strict"
  "archive|scripts/release-archive.sh"
  "dmg|scripts/release-dmg.sh"
  "artifact_verify|scripts/release-artifact-verify.sh"
  "release_draft_verify|scripts/release-draft-verify.sh"
)

if [[ -n "$app_path" ]]; then
  steps+=("installed_verify|scripts/release-installed-verify.sh --app-path \"$app_path\"")
else
  steps+=("installed_verify|SKIP (no app path detected)")
fi

results_file="$output_dir/step-results.tmp"
: >"$results_file"

run_step() {
  local step_name="$1"
  local step_cmd="$2"
  local log_file="$logs_dir/${step_name}.log"

  if [[ "$step_cmd" == SKIP* ]]; then
    local status="SKIP"
    {
      echo "$step_cmd"
    } >"$log_file"
    printf '%s|%s|%s\n' "$step_name" "$status" "$log_file" >>"$results_file"
    return
  fi

  if [[ $dry_run -eq 1 ]]; then
    local status="DRY_RUN"
    {
      echo "DRY RUN: $step_cmd"
    } >"$log_file"
    printf '%s|%s|%s\n' "$step_name" "$status" "$log_file" >>"$results_file"
    return
  fi

  local status
  if bash -lc "$step_cmd" >"$log_file" 2>&1; then
    status="PASS"
  else
    status="FAIL"
  fi
  printf '%s|%s|%s\n' "$step_name" "$status" "$log_file" >>"$results_file"
}

for step in "${steps[@]}"; do
  name="${step%%|*}"
  cmd="${step#*|}"
  run_step "$name" "$cmd"
done

if [[ $dry_run -eq 1 ]]; then
  overall_status="DRY_RUN"
elif rg -q '\|(FAIL|SKIP)\|' "$results_file"; then
  overall_status="PARTIAL"
else
  overall_status="PASS"
fi

step_status() {
  local target="$1"
  awk -F'|' -v target="$target" '$1 == target { print $2 }' "$results_file"
}

preflight_status="$(step_status preflight_strict)"
archive_status="$(step_status archive)"
dmg_status="$(step_status dmg)"
artifact_status="$(step_status artifact_verify)"
draft_status="$(step_status release_draft_verify)"
installed_status="$(step_status installed_verify)"

{
  echo "# Release-machine Closeout Summary"
  echo
  echo "**Date:** ${run_date}  "
  echo "**Overall status:** ${overall_status}  "
  echo "**Commit:** \`${commit_sha}\` — ${commit_subject}  "
  echo "**Pre-run worktree:** ${pre_run_worktree}  "
  echo "**Output dir:** \`${output_dir}\`"
  echo
  echo "## Step Results"
  echo
  echo "| Step | Status | Log |"
  echo "|---|---|---|"

  while IFS='|' read -r name status log_path; do
    echo "| ${name} | ${status} | \`${log_path}\` |"
  done <"$results_file"

  echo
  echo "## Closure Mapping"
  echo
  echo "- #96: \`preflight_strict\` + \`archive\` logs"
  echo "- #97: \`dmg\` + \`artifact_verify\` logs"
  echo "- #98: \`installed_verify\` log"
  echo "- #99: \`release_draft_verify\` + checksum from \`artifact_verify\`"
  echo "- #6: all above plus supervised live evidence (#124/#130)"
  echo
  echo "## GitHub Issue Update Snippets"
  echo
  echo "Copy these into the matching issue comments after reviewing logs for secrets."
  echo
  echo "### #96"
  echo
  echo '```markdown'
  echo "Release-machine closeout ${run_date} for commit \`${commit_sha}\`."
  echo
  echo "- Pre-run worktree: ${pre_run_worktree}"
  echo "- \`preflight_strict\`: ${preflight_status} (\`${logs_dir}/preflight_strict.log\`)"
  echo "- \`archive\`: ${archive_status} (\`${logs_dir}/archive.log\`)"
  echo
  echo "Maintainer acceptance note: #96 is ready only if both rows are PASS and the archive log records the signed \`.xcarchive\` from the clean release-machine checkout."
  echo '```'
  echo
  echo "### #97"
  echo
  echo '```markdown'
  echo "Release-machine closeout ${run_date} for commit \`${commit_sha}\`."
  echo
  echo "- \`dmg\`: ${dmg_status} (\`${logs_dir}/dmg.log\`)"
  echo "- \`artifact_verify\`: ${artifact_status} (\`${logs_dir}/artifact_verify.log\`)"
  echo
  echo "Maintainer acceptance note: #97 is ready only if notarization, stapling, Gatekeeper assessment, and SHA-256 checksum generation are all PASS."
  echo '```'
  echo
  echo "### #98"
  echo
  echo '```markdown'
  echo "Release-machine closeout ${run_date} for commit \`${commit_sha}\`."
  echo
  echo "- \`installed_verify\`: ${installed_status} (\`${logs_dir}/installed_verify.log\`)"
  echo
  echo "Maintainer acceptance note: #98 is ready only after the final notarized DMG installs and launches from a clean macOS user account."
  echo '```'
  echo
  echo "### #99"
  echo
  echo '```markdown'
  echo "Release-machine closeout ${run_date} for commit \`${commit_sha}\`."
  echo
  echo "- \`release_draft_verify\`: ${draft_status} (\`${logs_dir}/release_draft_verify.log\`)"
  echo "- Checksum source: \`${logs_dir}/artifact_verify.log\`"
  echo
  echo "Maintainer acceptance note: #99 is ready only after the release draft contains the exact final DMG checksum and artifact verification values."
  echo '```'
  echo
  echo "### #6"
  echo
  echo '```markdown'
  echo "Release-machine closeout ${run_date} for commit \`${commit_sha}\`."
  echo
  echo "- #96 archive gate: ${preflight_status}/${archive_status}"
  echo "- #97 DMG/notarization gate: ${dmg_status}/${artifact_status}"
  echo "- #98 clean-user install gate: ${installed_status}"
  echo "- #99 release notes/checksum gate: ${draft_status}"
  echo
  echo "Maintainer acceptance note: #6 still also needs supervised #124/#130 live QA evidence before the beta package lane is ready for final Done review."
  echo '```'
  echo
  echo "## Notes"
  echo
  echo "- Attach relevant logs and summary into issue comments before closure."
  echo "- If a step fails, fix the root cause and re-run this script to refresh evidence."
} >"$summary_path"

rm -f "$results_file"

echo "release-machine-closeout.sh: wrote $summary_path"
