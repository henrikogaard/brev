#!/usr/bin/env bash
# Self-test for the --provider flag in imap-smtp-live-smoke.sh.
# Requires no credentials and makes no network calls.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# Verify --provider is documented in usage.
"$ROOT/scripts/imap-smtp-live-smoke.sh" --help | grep -q "\-\-provider" \
  || fail "--provider not found in --help output"
pass "--provider is documented in --help output"

# Verify supported providers are listed in usage.
for provider in fastmail icloud yahoo gmail outlook mailboxorg; do
  "$ROOT/scripts/imap-smtp-live-smoke.sh" --help | grep -q "$provider" \
    || fail "provider '$provider' not documented in --help output"
  pass "provider '$provider' is mentioned in --help output"
done

# Verify unknown provider exits non-zero.
"$ROOT/scripts/imap-smtp-live-smoke.sh" --provider unknown_xyz 2>/dev/null \
  && fail "--provider unknown_xyz should have exited non-zero" \
  || pass "--provider unknown_xyz correctly exits non-zero"

# Verify --provider without a value exits non-zero.
"$ROOT/scripts/imap-smtp-live-smoke.sh" --provider 2>/dev/null \
  && fail "--provider with no value should have exited non-zero" \
  || pass "--provider with no value correctly exits non-zero"

# Verify that --provider with a valid name alongside missing credentials
# produces a clean skip (exit 0), not a usage error.
output="$(BREV_LIVE_MAIL_EMAIL="" BREV_LIVE_MAIL_PASSWORD="" BREV_LIVE_IMAP_HOST="" \
  "$ROOT/scripts/imap-smtp-live-smoke.sh" --provider fastmail 2>&1 || true)"
echo "$output" | grep -q "skipped" \
  || fail "--provider fastmail without credentials should produce a skip message; got: $output"
pass "--provider fastmail without credentials produces a clean skip"

echo "test-live-smoke-provider-flag: all checks passed"
