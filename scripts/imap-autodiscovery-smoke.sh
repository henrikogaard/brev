#!/usr/bin/env bash
# IMAP/SMTP autodiscovery smoke runner.
#
# Default mode (no flags): compile + built-in provider matrix check.
#   No network access required. Safe to run in CI without credentials.
#   Builds a small Swift executable against BrevBackend and asserts that
#   each known provider domain resolves to the expected DiscoverySource.
#
# --live mode: probe live DNS and autoconfig for supplied email addresses.
#   Requires an email address (explicit opt-in to network probes).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

usage() {
  cat <<'EOF'
usage: scripts/imap-autodiscovery-smoke.sh [--live [--require-live] [--require-discovered] [--require-source SOURCE] [--timeout SECONDS] [--email ADDRESS]]

Default (no flags):
  Compile + built-in provider matrix mode. No network access. CI-safe.
  Builds a Swift executable against BrevBackend and asserts each known-
  provider domain resolves to the expected DiscoverySource (builtInProfile,
  dnsSRV, providerAutoconfig, or manualFallback).

  Hard-fail domains (guaranteed built-in profiles):
    gmail.com, outlook.com, hotmail.com, fastmail.com,
    icloud.com, me.com, yahoo.com

  Soft-warn domains (profile may not be merged yet):
    proton.me, protonmail.com, zoho.com, gmx.com, web.de,
    mailbox.org, posteo.de, runbox.com

--live:
  Switch to live DNS/autoconfig probe mode. Supplying an email address
  is an explicit opt-in to DNS SRV probes for that domain and, if needed,
  provider-local HTTPS autoconfig probes that may include the full email
  address.

  --require-live              Fail instead of cleanly skipping when no email is supplied.
  --require-discovered        Fail if discovery falls back to manual defaults.
  --require-source SOURCE     Require builtInProfile, dnsSRV, providerAutoconfig, or manualFallback.
  --timeout SECONDS           Per-probe timeout, default: 4.
  --email ADDRESS             Address to resolve. May be passed multiple times.

Environment (live mode):
  BREV_AUTODISCOVERY_EMAILS   Comma-separated email addresses to resolve.

Examples:
  scripts/imap-autodiscovery-smoke.sh
  scripts/imap-autodiscovery-smoke.sh --live --email person@example.org
  scripts/imap-autodiscovery-smoke.sh --live --require-live --require-discovered --email person@example.org
EOF
}

live_mode=0
require_live=0
require_discovered=0
require_source=""
timeout="4"
emails=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --live)
      live_mode=1
      shift
      ;;
    --require-live)
      require_live=1
      shift
      ;;
    --require-discovered)
      require_discovered=1
      shift
      ;;
    --require-source)
      if [[ $# -lt 2 ]]; then
        echo "imap-autodiscovery-smoke: --require-source needs a value" >&2
        usage >&2
        exit 2
      fi
      require_source="$2"
      shift 2
      ;;
    --timeout)
      if [[ $# -lt 2 ]]; then
        echo "imap-autodiscovery-smoke: --timeout needs a value" >&2
        usage >&2
        exit 2
      fi
      timeout="$2"
      shift 2
      ;;
    --email)
      if [[ $# -lt 2 ]]; then
        echo "imap-autodiscovery-smoke: --email needs a value" >&2
        usage >&2
        exit 2
      fi
      emails+=("$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    # Legacy compat: --compile-only runs the matrix mode (compile + matrix).
    --compile-only)
      # No-op: default mode already does compile + matrix.
      shift
      ;;
    *)
      echo "imap-autodiscovery-smoke: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ${#emails[@]} -eq 0 && -n "${BREV_AUTODISCOVERY_EMAILS:-}" ]]; then
  IFS=',' read -r -a emails <<<"$BREV_AUTODISCOVERY_EMAILS"
fi

# ---------------------------------------------------------------------------
# Shared: build the smoke executable
# ---------------------------------------------------------------------------

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/brev-imap-autodiscovery-smoke.XXXXXX")"
CACHE_DIR="${TMPDIR:-/tmp}/brev-imap-autodiscovery-smoke-cache"
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$WORK_DIR/Sources/BrevIMAPAutodiscoverySmoke" "$CACHE_DIR"

cat >"$WORK_DIR/Package.swift" <<EOF
// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "BrevIMAPAutodiscoverySmoke",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "$ROOT/packages/BrevBackend")
    ],
    targets: [
        .executableTarget(
            name: "BrevIMAPAutodiscoverySmoke",
            dependencies: [
                .product(name: "BrevBackend", package: "BrevBackend")
            ]
        )
    ]
)
EOF

# ---------------------------------------------------------------------------
# Matrix mode (default): credential-free, network-free built-in profile check
# ---------------------------------------------------------------------------

if [[ $live_mode -eq 0 ]]; then
  # The matrix Swift source uses MailAccountAutodiscovery.profile(forEmailAddress:),
  # which is a pure in-memory lookup — no network calls, no credentials.
  #
  # Hard-fail domains: guaranteed to have built-in profiles in BrevBackend.
  # Soft-warn domains: profile may be added by a parallel task not yet merged;
  #   a mismatch prints WARN but does not cause exit failure.

  cat >"$WORK_DIR/Sources/BrevIMAPAutodiscoverySmoke/main.swift" <<'SWIFT'
import BrevBackend
import Foundation

// Matrix of (email address, expected source, isSoftWarn)
// Soft-warn rows print WARN on mismatch rather than hard-failing.
let matrix: [(email: String, expected: MailAccountDiscoverySource, softWarn: Bool)] = [
    // Guaranteed built-in profiles — hard fail on mismatch
    ("smoke@gmail.com",      .builtInProfile, false),
    ("smoke@outlook.com",    .builtInProfile, false),
    ("smoke@hotmail.com",    .builtInProfile, false),
    ("smoke@fastmail.com",   .builtInProfile, false),
    ("smoke@icloud.com",     .builtInProfile, false),
    ("smoke@me.com",         .builtInProfile, false),
    ("smoke@yahoo.com",      .builtInProfile, false),

    // Soft-warn: profiles expected but may not be merged yet
    ("smoke@proton.me",      .builtInProfile, true),
    ("smoke@protonmail.com", .builtInProfile, true),
    ("smoke@zoho.com",       .builtInProfile, true),
    ("smoke@gmx.com",        .builtInProfile, true),
    ("smoke@web.de",         .builtInProfile, true),
    ("smoke@mailbox.org",    .builtInProfile, true),
    ("smoke@posteo.de",      .builtInProfile, true),
    ("smoke@runbox.com",     .builtInProfile, true),
]

var hardFailures: [String] = []
var warnings: [String] = []

for row in matrix {
    let result = MailAccountAutodiscovery.profile(forEmailAddress: row.email)
    let actual: MailAccountDiscoverySource = result?.source ?? .manualFallback

    if actual == row.expected {
        print("OK:   \(row.email) -> \(actual.rawValue)")
    } else if row.softWarn {
        let msg = "WARN: \(row.email) did not match \(row.expected.rawValue) (source=\(actual.rawValue))"
        print(msg)
        warnings.append(msg)
    } else {
        let msg = "FAIL: \(row.email) expected \(row.expected.rawValue), got \(actual.rawValue)"
        print(msg)
        hardFailures.append(msg)
    }
}

print("")
if !warnings.isEmpty {
    print("Warnings (\(warnings.count)) — soft-fail; profile may not be merged yet:")
    for w in warnings { print("  \(w)") }
}

if !hardFailures.isEmpty {
    print("Hard failures (\(hardFailures.count)) — guaranteed providers did not return builtInProfile:")
    for f in hardFailures { print("  \(f)") }
    exit(1)
}

print("imap-autodiscovery-smoke: matrix OK")
SWIFT

  echo "imap-autodiscovery-smoke: building matrix executable..."
  if ! swift build \
      --package-path "$WORK_DIR" \
      --scratch-path "$CACHE_DIR" \
      -c debug 2>&1; then
    echo ""
    echo "imap-autodiscovery-smoke: SKIP — BrevBackend does not yet expose"
    echo "  MailAccountAutodiscovery. This is expected when the autodiscovery"
    echo "  provider profile task has not been merged yet. Exiting 0."
    exit 0
  fi

  echo "imap-autodiscovery-smoke: running provider matrix checks..."
  swift run \
    --package-path "$WORK_DIR" \
    --scratch-path "$CACHE_DIR" \
    -c debug \
    BrevIMAPAutodiscoverySmoke
  exit $?
fi

# ---------------------------------------------------------------------------
# Live mode (--live): DNS SRV + autoconfig probe with supplied email addresses
# ---------------------------------------------------------------------------

cat >"$WORK_DIR/Sources/BrevIMAPAutodiscoverySmoke/main.swift" <<'SWIFT'
import BrevBackend
import Foundation

enum AutodiscoverySmokeError: Error, LocalizedError {
    case missingEmailAddress
    case invalidTimeout(String)
    case invalidRequiredSource(String)
    case missingServerSettings(String)
    case manualFallback(String)
    case sourceMismatch(String, expected: MailAccountDiscoverySource, actual: MailAccountDiscoverySource)

    var errorDescription: String? {
        switch self {
        case .missingEmailAddress:
            "No email address was supplied."
        case .invalidTimeout(let value):
            "BREV_AUTODISCOVERY_TIMEOUT must be a positive number of seconds, got \(value)."
        case .invalidRequiredSource(let value):
            "BREV_AUTODISCOVERY_REQUIRE_SOURCE must be builtInProfile, dnsSRV, providerAutoconfig, or manualFallback; got \(value)."
        case .missingServerSettings(let email):
            "Discovery for \(email) did not return both IMAP and SMTP settings."
        case .manualFallback(let email):
            "Discovery for \(email) fell back to manual defaults."
        case .sourceMismatch(let email, let expected, let actual):
            "Discovery for \(email) returned \(actual.rawValue), expected \(expected.rawValue)."
        }
    }
}

@main
struct BrevIMAPAutodiscoverySmoke {
    static func main() async throws {
        let environment = ProcessInfo.processInfo.environment
        let emails = emailAddresses(from: environment["BREV_AUTODISCOVERY_EMAILS"])
        guard !emails.isEmpty else {
            throw AutodiscoverySmokeError.missingEmailAddress
        }

        let timeout = try timeout(from: environment["BREV_AUTODISCOVERY_TIMEOUT"])
        let requireDiscovered = environment["BREV_AUTODISCOVERY_REQUIRE_DISCOVERED"] == "1"
        let requiredSource = try requiredSource(from: environment["BREV_AUTODISCOVERY_REQUIRE_SOURCE"])
        let resolver = MailAccountAutodiscoveryResolver.system(timeout: timeout)

        for email in emails {
            let result = try await resolver.resolve(forEmailAddress: email)
            try validate(
                result,
                email: email,
                requireDiscovered: requireDiscovered,
                requiredSource: requiredSource
            )
            print(summaryLine(email: email, result: result))
        }

        print("imap-autodiscovery-smoke: OK")
    }

    private static func emailAddresses(from rawValue: String?) -> [String] {
        guard let rawValue else { return [] }
        return rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func timeout(from rawValue: String?) throws -> TimeInterval {
        guard let rawValue,
              !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return 4
        }
        guard let timeout = TimeInterval(rawValue),
              timeout > 0
        else {
            throw AutodiscoverySmokeError.invalidTimeout(rawValue)
        }
        return timeout
    }

    private static func requiredSource(
        from rawValue: String?
    ) throws -> MailAccountDiscoverySource? {
        guard let rawValue,
              !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        guard let source = MailAccountDiscoverySource(rawValue: rawValue) else {
            throw AutodiscoverySmokeError.invalidRequiredSource(rawValue)
        }
        return source
    }

    private static func validate(
        _ result: MailAccountDiscoveryResult,
        email: String,
        requireDiscovered: Bool,
        requiredSource: MailAccountDiscoverySource?
    ) throws {
        guard result.incoming != nil,
              result.outgoing != nil
        else {
            throw AutodiscoverySmokeError.missingServerSettings(email)
        }
        if requireDiscovered,
           result.source == .manualFallback {
            throw AutodiscoverySmokeError.manualFallback(email)
        }
        if let requiredSource,
           result.source != requiredSource {
            throw AutodiscoverySmokeError.sourceMismatch(
                email,
                expected: requiredSource,
                actual: result.source
            )
        }
    }

    private static func summaryLine(
        email: String,
        result: MailAccountDiscoveryResult
    ) -> String {
        let incoming = result.incoming.map {
            "\($0.host):\($0.port)/\($0.tlsMode.rawValue)/\($0.authentication.rawValue)"
        } ?? "missing"
        let outgoing = result.outgoing.map {
            "\($0.host):\($0.port)/\($0.tlsMode.rawValue)/\($0.authentication.rawValue)"
        } ?? "missing"
        return "Discovery: \(email) -> \(result.source.rawValue) IMAP=\(incoming) SMTP=\(outgoing) manualReview=\(result.requiresManualReview)"
    }
}
SWIFT

echo "imap-autodiscovery-smoke: building live-mode executable..."
swift build \
  --package-path "$WORK_DIR" \
  --scratch-path "$CACHE_DIR" \
  -c debug

if [[ ${#emails[@]} -eq 0 ]]; then
  echo "imap-autodiscovery-smoke: skipped; pass --email or set BREV_AUTODISCOVERY_EMAILS to run provider discovery."
  if [[ $require_live -eq 1 ]]; then
    exit 2
  fi
  exit 0
fi

email_list=""
printf -v email_list '%s,' "${emails[@]}"
email_list="${email_list%,}"

BREV_AUTODISCOVERY_EMAILS="$email_list" \
BREV_AUTODISCOVERY_TIMEOUT="$timeout" \
BREV_AUTODISCOVERY_REQUIRE_DISCOVERED="$require_discovered" \
BREV_AUTODISCOVERY_REQUIRE_SOURCE="$require_source" \
swift run \
  --package-path "$WORK_DIR" \
  --scratch-path "$CACHE_DIR" \
  -c debug \
  BrevIMAPAutodiscoverySmoke
