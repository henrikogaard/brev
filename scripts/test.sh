#!/usr/bin/env bash
# Runs Brev's SPM-package unit tests on the host (macOS).
#
# Snapshot suites (`BrevDesignSnapshotTests`, `BrevMailSnapshotTests`)
# are UIKit-gated and skipped on the host — run those from Xcode
# against an iOS simulator destination, or extend this script with
# `xcodebuild test` once a shared scheme is wired up.
#
# Packages that intentionally have no test target are built instead.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SELF_TESTS_ONLY=0

usage() {
    cat <<'EOF'
usage: scripts/test.sh [--self-tests-only]

Run repository self-tests and package tests. Use --self-tests-only in CI when
the package matrix already runs the Swift package suites.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --self-tests-only)
            SELF_TESTS_ONLY=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "test.sh: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

# Shipping packages only.
PACKAGES=(
    BrevAI
    BrevAvatars
    BrevBackend
    BrevCalendar
    BrevDesign
    BrevMail
    BrevSettings
    BrevThemes
)

cd "$ROOT"

echo "── build/run env ──"
scripts/test-build-run-env.sh

echo "── local build versioning ──"
scripts/test-local-build-version.sh

echo "── Apple distribution team ──"
scripts/test-apple-team-config.sh

echo "── desktop compact layout ──"
scripts/test-desktop-compact-layout-check.sh

echo "── iOS extension plists ──"
scripts/test-ios-extension-plists.sh

echo "── live smoke provider flag ──"
scripts/test-live-smoke-provider-flag.sh

echo "── public source markers ──"
scripts/test-public-source-markers.sh

echo "── privacy audit coverage ──"
scripts/test-privacy-audit-coverage.sh

echo "── remote push retirement ──"
scripts/test-remote-push-retired.sh

echo "── OpenPGP retirement ──"
bash scripts/test-openpgp-retired.sh

echo "── iOS privacy manifest ──"
scripts/test-ios-privacy-manifest.sh

echo "── internal TestFlight export policy ──"
scripts/test-testflight-export-options.sh

echo "── Developer ID release policy ──"
scripts/test-developer-id-release-config.sh

echo "── telemetry artifacts ──"
scripts/test-telemetry-artifacts.sh

if [[ "$SELF_TESTS_ONLY" -eq 1 ]]; then
    echo "test.sh: self-tests OK"
    exit 0
fi

for pkg in "${PACKAGES[@]}"; do
    echo "── ${pkg} ──"
    if [[ -f "packages/${pkg}/Package.swift" && -d "packages/${pkg}/Tests" ]]; then
        test_args=(--disable-build-manifest-caching --package-path "packages/${pkg}")
        if [[ "$pkg" == "BrevDesign" ]]; then
            # Xcode 27's Swift Testing host can crash after both BrevDesign
            # suites pass when the helper uses its default worker scheduling.
            # One parallel worker keeps both suites in one deterministic run
            # without changing the production test surface.
            test_args+=(--parallel --num-workers 1)
        fi
        swift test "${test_args[@]}"
    elif [[ -f "packages/${pkg}/Package.swift" ]]; then
        swift build --disable-build-manifest-caching --package-path "packages/${pkg}"
    elif [[ -f "packages/${pkg}/Project.swift" ]]; then
        mise exec -- tuist test "${pkg}" --clean --no-binary-cache --no-selective-testing
    else
        echo "missing Package.swift or Project.swift for packages/${pkg}" >&2
        exit 1
    fi
done

echo "test.sh: OK"
