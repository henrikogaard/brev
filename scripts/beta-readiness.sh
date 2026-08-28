#!/usr/bin/env bash
# beta-readiness.sh — One-command local beta readiness gate.
#
# The default mode runs checks that are safe on any development machine.
# Use --full for heavier local build/smoke checks and --release-machine on
# Henrik's signing/notarization machine after artifacts exist.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mode="local"

usage() {
  cat <<'EOF'
usage: scripts/beta-readiness.sh [--local|--full|--release-machine|--perf]

Modes:
  --local            Fast non-secret readiness checks. This is the default.
  --full             Local checks plus workspace preparation and mock smoke.
  --release-machine  Local checks plus release artifact/install gates when
                     BREV_DMG_PATH or BREV_APP_PATH point at built artifacts.
  --perf             Local checks plus performance budget policy self-test.

Environment used by --release-machine:
  BREV_DMG_PATH          Optional DMG path for artifact and installed checks.
  BREV_APP_PATH          Optional installed app path for installed checks.
  BREV_SKIP_GATEKEEPER   Set to 1 only for local debug artifacts.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local)
      mode="local"
      shift
      ;;
    --full)
      mode="full"
      shift
      ;;
    --release-machine)
      mode="release-machine"
      shift
      ;;
    --perf)
      mode="perf"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "beta-readiness.sh: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

failures=0
skips=0

run_step() {
  local name="$1"
  shift
  echo "==> ${name}"
  if "$@"; then
    echo "    PASS: ${name}"
  else
    echo "    FAIL: ${name}" >&2
    failures=$((failures + 1))
  fi
}

skip_step() {
  local name="$1"
  local reason="$2"
  echo "==> ${name}"
  echo "    SKIP: ${reason}"
  skips=$((skips + 1))
}

require_file() {
  local path="$1"
  if [[ -f "$path" ]]; then
    echo "    OK: ${path}"
  else
    echo "    MISSING: ${path}" >&2
    return 1
  fi
}

check_required_docs() {
  require_file docs/release.md
  require_file docs/qa/desktop-smoke.md
  require_file docs/qa/ios-ipados-surface-matrix.md
  require_file docs/releases/macos-beta-github-release-draft.md
}

check_worktree_hygiene() {
  git diff --check
  if git diff --quiet && git diff --cached --quiet; then
    echo "    OK: working tree clean"
  else
    echo "    WARN: working tree has uncommitted changes; beta artifacts should come from a clean checkout"
  fi
}

run_step "required release and QA docs" check_required_docs
run_step "diff hygiene" check_worktree_hygiene
run_step "lint" scripts/lint.sh
run_step "privacy audit" scripts/privacy-audit.sh
run_step "release preflight" scripts/release-preflight.sh
run_step "iOS extension plist/scheme validation" scripts/test-ios-extension-plists.sh
run_step "GitHub release draft verification" scripts/release-draft-verify.sh

case "$mode" in
  local)
    skip_step "workspace preparation and mock smoke" "use --full for heavier local build/smoke checks"
    skip_step "release artifact/install verification" "use --release-machine after DMG/app artifacts exist"
    ;;
  full)
    run_step "workspace preparation" scripts/prepare-xcode-workspace.sh
    run_step "desktop mock smoke" scripts/release-smoke.sh
    skip_step "release artifact/install verification" "use --release-machine after DMG/app artifacts exist"
    ;;
  release-machine)
    if [[ -n "${BREV_DMG_PATH:-}" || -f build/release/BrevMail.dmg ]]; then
      artifact_args=()
      if [[ -n "${BREV_DMG_PATH:-}" ]]; then
        artifact_args+=(--dmg-path "$BREV_DMG_PATH")
      fi
      run_step "release artifact verification" scripts/release-artifact-verify.sh "${artifact_args[@]}"
    else
      skip_step "release artifact verification" "no DMG found; set BREV_DMG_PATH or create build/release/BrevMail.dmg"
    fi

    if [[ -n "${BREV_APP_PATH:-}" || -n "${BREV_DMG_PATH:-}" ]]; then
      run_step "installed-build smoke handoff" scripts/release-smoke.sh --installed
    else
      skip_step "installed-build smoke handoff" "set BREV_APP_PATH or BREV_DMG_PATH after packaging"
    fi
    ;;
  perf)
    run_step "performance budget policy self-test" scripts/performance-budget-gate.sh --self-test
    skip_step "live performance measurement gate" "provide BREV_PERF_RESULTS_JSON for hard budget evaluation"
    ;;
esac

if [[ $failures -ne 0 ]]; then
  echo "beta-readiness.sh: ${failures} failure(s), ${skips} skipped step(s)" >&2
  exit 1
fi

echo "beta-readiness.sh: OK (${skips} skipped step(s))"
