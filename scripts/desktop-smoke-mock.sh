#!/usr/bin/env bash
# Repeatable no-OAuth desktop smoke gate.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> package tests"
scripts/test.sh

echo "==> format"
scripts/format.sh

echo "==> lint"
scripts/lint.sh

echo "==> git diff --check"
git diff --check

echo "==> literal color scan"
set +e
literal_color_output="$(
  # A bare hex literal is only valid Swift inside a string (e.g. Color(hex: "#1A2B3C")),
  # so require the surrounding quote — otherwise issue references in comments like
  # `// #150` or `(The related feature request)` are misread as 3-digit hex colors.
  # HTMLBodyWebView is exempt: it emits CSS color strings to render email HTML in a
  # WebView (not SwiftUI theme colors), which the authoritative swiftlint
  # `no_literal_colors_in_views` rule also does not flag (ADR-0002).
  rg -n \
    'Color\.(black|blue|brown|cyan|gray|green|indigo|mint|orange|pink|purple|red|teal|white|yellow)|Color\(hex:|"#[0-9A-Fa-f]{3,8}"' \
    apps \
    packages/BrevDesign/Sources \
    packages/BrevMail/Sources \
    packages/BrevSettings/Sources \
    --glob '*.swift' \
    --glob '!**/HTMLBodyWebView.swift' 2>&1
)"
literal_color_status=$?
set -e

if [[ $literal_color_status -eq 0 ]]; then
  echo "$literal_color_output"
  echo "desktop-smoke-mock.sh: literal color scan found matches" >&2
  exit 1
elif [[ $literal_color_status -gt 1 ]]; then
  echo "$literal_color_output" >&2
  exit "$literal_color_status"
fi
echo "    OK"

echo "==> privacy audit"
scripts/privacy-audit.sh

echo "==> mock build and launch verification"
./script/build_and_run.sh --mock --verify

echo "desktop-smoke-mock.sh: OK"
