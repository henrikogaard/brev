#!/usr/bin/env bash
# Verify that SwiftLint's localization and UI-invariant gates cover every
# extension/plugin source root. The synthetic fixtures are created below the
# real roots so custom-rule path matching is tested, then removed on exit.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$ROOT/.swiftlint.yml"

if ! command -v ruby >/dev/null 2>&1; then
  echo "test-swiftlint-coverage: ruby is required to inspect YAML" >&2
  exit 127
fi

ruby -ryaml -e '
  config = YAML.load_file(ARGV.fetch(0))
  required_roots = [
    "Plugins",
    "apps/iOS/BrevShareExtension",
    "apps/iOS/BrevNotificationContent"
  ]
  included = config.fetch("included")
  missing_roots = required_roots.reject { |root| included.include?(root) }
  abort "missing SwiftLint included roots: #{missing_roots.join(", ")}" unless missing_roots.empty?

  disabled = config.fetch("disabled_rules")
  opt_in = config.fetch("opt_in_rules")
  overlap = disabled & opt_in
  abort "SwiftLint rule appears in both disabled_rules and opt_in_rules: #{overlap.join(", ")}" unless overlap.empty?

  rules = config.fetch("custom_rules")
  required_rule_paths = {
    "no_literal_colors_in_views" => [
      "Plugins/.*/Sources/.*\\.swift",
      "apps/iOS/BrevShareExtension/.*\\.swift",
      "apps/iOS/BrevNotificationContent/.*\\.swift"
    ],
    "no_hardcoded_view_strings" => ["Plugins/.*/Sources/.*\\.swift"],
    "package_text_missing_module_bundle" => [
      "Plugins/.*/Sources/.*\\.swift",
      "packages/BrevMail/Sources/.*\\.swift"
    ]
  }
  required_rule_paths.each do |rule_name, paths|
    configured = rules.fetch(rule_name).fetch("included")
    missing = paths.reject { |path| configured.include?(path) }
    abort "#{rule_name} is missing paths: #{missing.join(", ")}" unless missing.empty?
  end
' "$CONFIG"

if command -v mise >/dev/null 2>&1; then
  SWIFTLINT=(mise exec -- swiftlint)
elif command -v swiftlint >/dev/null 2>&1; then
  SWIFTLINT=(swiftlint)
else
  echo "test-swiftlint-coverage: swiftlint is required" >&2
  exit 127
fi

plugin_root="$(mktemp -d "$ROOT/Plugins/.swiftlint-coverage.XXXXXX")"
share_fixture="$(mktemp "$ROOT/apps/iOS/BrevShareExtension/.swiftlint-coverage.XXXXXX.swift")"
notification_fixture="$(mktemp "$ROOT/apps/iOS/BrevNotificationContent/.swiftlint-coverage.XXXXXX.swift")"
brevmail_fixture="$(mktemp "$ROOT/packages/BrevMail/Sources/BrevMail/.swiftlint-coverage.XXXXXX.swift")"

cleanup() {
  find "$plugin_root" -type f -delete
  find "$plugin_root" -depth -type d -empty -delete
  find "$ROOT/apps/iOS/BrevShareExtension" -maxdepth 1 -name '.swiftlint-coverage.*.swift' -type f -delete
  find "$ROOT/apps/iOS/BrevNotificationContent" -maxdepth 1 -name '.swiftlint-coverage.*.swift' -type f -delete
  find "$ROOT/packages/BrevMail/Sources/BrevMail" -maxdepth 1 -name '.swiftlint-coverage.*.swift' -type f -delete
}
trap cleanup EXIT

plugin_fixture="$plugin_root/Sources/Probe/Probe.swift"
mkdir -p "$(dirname "$plugin_fixture")"
fixture_source='import SwiftUI

struct LintFixture: View {
    var body: some View {
        Text("Fixture").foregroundStyle(Color.red)
    }
}'
printf '%s\n' "$fixture_source" > "$plugin_fixture"
printf '%s\n' "$fixture_source" > "$share_fixture"
printf '%s\n' "$fixture_source" > "$notification_fixture"
printf '%s\n' 'import SwiftUI' '' 'struct LintFixture: View {' '    var body: some View {' '        Text("Fixture")' '    }' '}' > "$brevmail_fixture"

check_fixture() {
  local fixture="$1"
  shift
  local output
  local status
  set +e
  output="$("${SWIFTLINT[@]}" lint --config "$CONFIG" --strict --quiet "$fixture" 2>&1)"
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    echo "test-swiftlint-coverage: fixture unexpectedly passed: $fixture" >&2
    return 1
  fi
  for rule in "$@"; do
    if [[ "$output" != *"($rule)"* ]]; then
      echo "test-swiftlint-coverage: $rule did not fire for $fixture" >&2
      printf '%s\n' "$output" >&2
      return 1
    fi
  done
}

check_fixture "$plugin_fixture" \
  no_literal_colors_in_views \
  no_hardcoded_view_strings \
  package_text_missing_module_bundle
check_fixture "$share_fixture" \
  no_literal_colors_in_views \
  no_hardcoded_view_strings
check_fixture "$notification_fixture" \
  no_literal_colors_in_views \
  no_hardcoded_view_strings
check_fixture "$brevmail_fixture" \
  package_text_missing_module_bundle

echo "test-swiftlint-coverage: OK"
