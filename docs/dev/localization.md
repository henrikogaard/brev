# Localization

Brev ships `en` only today, but the pipeline is fully catalog-native:
every package and app target carries a `Localizable.xcstrings` String
Catalog, and view code uses `String(localized:)` (app targets) or
`String(localized:bundle:.module)` (SPM packages) per ADR-0058.

## Adding a language

1. In Xcode, select the project → Info → Localizations → `+` → pick the
   locale (e.g. Norwegian Bokmål `nb`). Xcode adds the language to every
   `.xcstrings` catalog automatically.
2. `tuist generate` afterwards so Tuist picks up the catalog changes.
3. Translate in the Xcode String Catalog editor (or export `xliff` for
   external tools: Product → Export Localizations).
4. Untranslated keys fall back to the source language — partial
   translations are safe to ship, but keep a language either complete
   or unreleased for a release build.

## Rules for new strings

- Never a bare literal in `Text`, `NSAlert`, `LocalizedError`, or
  accessibility labels — always `String(localized:…)` so extraction
  picks it up.
- Use descriptive keys in English; comments (`comment:`) where the
  context is ambiguous (single words like "Archive" are verbs AND
  nouns — say which).
- Plurals go through catalog variations, not `String(format:)` with
  `%d items` pasted together.
- Snapshot tests run in `en`; new localized keys do not need new
  baselines.

## Community translation workflow (OSS)

- Translators edit `Localizable.xcstrings` directly or via exported
  `xliff`; PRs titled `l10n(<locale>): …`.
- Malformed catalog JSON fails at build time — Xcode compiles
  `.xcstrings` during the app build, so a broken catalog surfaces on
  `tuist generate` + build. `scripts/lint.sh` does **not** parse
  catalogs; translators should verify with a build, and a future
  CI step could `plutil -lint` the catalogs if we want a faster
  signal.
- Aim for one locale steward per language — note them in this file as
  languages land.
