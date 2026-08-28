#!/usr/bin/env bash
# release-smoke.sh — Run the desktop smoke checklist against mock and/or installed build.
#
# Usage:
#   scripts/release-smoke.sh               # mock mode (automated gate)
#   scripts/release-smoke.sh --installed   # installed DMG (manual checklist reminder)
#   scripts/release-smoke.sh --live        # live-mode preflight (needs OAuth creds)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MODE="mock"
for arg in "$@"; do
  [[ "$arg" == "--installed" ]] && MODE="installed"
  [[ "$arg" == "--live" ]]      && MODE="live"
done

echo "=== Brev Desktop Smoke — $MODE mode ==="

case "$MODE" in
  mock)
    # Run the automated mock-mode gate.
    bash "$SCRIPT_DIR/desktop-smoke-mock.sh"
    ;;
  installed)
    # Installed-build smoke: run automated installed-app checks, then manual checklist.
    echo ""
    echo "Running installed-app automated checks..."
    verify_args=()
    if [[ -n "${BREV_APP_PATH:-}" ]]; then
      verify_args+=(--app-path "$BREV_APP_PATH")
    fi
    if [[ -n "${BREV_DMG_PATH:-}" ]]; then
      verify_args+=(--dmg-path "$BREV_DMG_PATH")
    fi
    if [[ "${BREV_SKIP_GATEKEEPER:-0}" == "1" ]]; then
      verify_args+=(--skip-gatekeeper)
    fi
    bash "$SCRIPT_DIR/release-installed-verify.sh" ${verify_args[@]+"${verify_args[@]}"}
    echo ""
    echo "Installed-build smoke checklist:"
    echo "  1. Mount BrevMail.dmg and drag Brev.app into /Applications."
    echo "  2. Confirm release-installed-verify gate above passes."
    echo "  3. Work through docs/qa/desktop-smoke.md manually."
    echo "  4. Record results in docs/smoke-checklist-results-$(date +%Y-%m-%d)-installed.md"
    echo ""
    echo "Frozen scope: no window-material findings should be filed as"
    echo "implementation issues. See docs/qa/desktop-smoke.md §Window."
    ;;
  live)
    ENV_FILE="$REPO_ROOT/.env.local"
    [[ -f "$ENV_FILE" ]] && { set -a; source "$ENV_FILE"; set +a; }
    bash "$SCRIPT_DIR/release-preflight.sh" --live
    echo ""
    echo "If preflight reports live OAuth ready, run:"
    echo "  ./script/build_and_run.sh --live --logs"
    echo "Then work through the live sections of docs/qa/desktop-smoke.md."
    ;;
esac

echo ""
echo "Smoke complete."
