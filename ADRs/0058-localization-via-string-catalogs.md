# ADR-0058: Localization via String Catalogs

- **Status:** Accepted
- **Date:** 2026-08-16
- **Deciders:** Henrik

## Context

Brev has shipped English-only since inception. User-visible strings are
scattered as literals across the two app targets and several packages —
SwiftUI `Text("...")`, `LocalizedStringKey` parameters, `NSAlert` /
`NSSavePanel` / `NSOpenPanel` text on macOS, `UILabel.text` /
`UIButton` titles in the iOS share extension and notification content
extension, `LocalizedError.errorDescription` on backend and package
error types, and `Info.plist` values such as `CFBundleDisplayName` and
the various `NS*UsageDescription` permission strings.

None of this is wired into Apple's String Catalog (`.xcstrings`)
system. Adding a language today would mean hand-building `.strings`
files and manually keeping them in sync with source, with no tooling
support for finding new or stale strings.

Xcode 15+ / Swift 5.9+ supports automatic string extraction into
`.xcstrings` catalogs via `SWIFT_EMIT_LOC_STRINGS =
YES`, when combined with `String(localized:)` (non-SwiftUI call
sites), `Text("...")` / `LocalizedStringKey`-typed SwiftUI parameters,
and NSLocalizedString equivalents. SPM package targets that vend
SwiftUI views need an explicit `bundle: .module` argument, because
`Text`'s default bundle resolution assumes the main app bundle and
silently fails to find package-local catalogs otherwise.

This ADR establishes the infrastructure and per-target/package
conventions. It does not add a second language — that is a follow-up
once native-speaker review is available for translated strings.

## Decision

1. **Build settings.** Both app targets (`BrevMacOS`, `BrevIOS`) set
   `SWIFT_EMIT_LOC_STRINGS = YES` and
   `LOCALIZATION_PREFERS_STRING_CATALOGS = YES` in their Tuist
   `Project.swift` base settings. `knownRegions` already listed `en`
   as the sole development region; no change was needed there.

2. **Catalogs per target.**
   - `apps/macOS/Resources/Localizable.xcstrings` and
     `apps/iOS/Resources/Localizable.xcstrings` hold app-target
     strings, wired as target resources in `Project.swift`.
   - `apps/macOS/Resources/InfoPlist.xcstrings` and
     `apps/iOS/Resources/InfoPlist.xcstrings` hold the
     `Info.plist`-sourced strings (`CFBundleDisplayName`,
     `CFBundleName`, `NSHumanReadableCopyright`, and the Contacts /
     Calendars / Reminders usage-description strings), seeded from
     the existing English values in each `Info.plist`.
   - `apps/iOS/BrevShareExtension/Resources/Localizable.xcstrings`
     holds the share extension's UIKit label/button strings, since it
     builds as its own app-extension target with its own bundle.
   - The notification-content extension has no user-authored strings
     of its own (it renders sender/subject/snippet text supplied by
     the host app's notification payload), so it gets no catalog.
   - Build-time plugins that ship user-facing SwiftUI, such as the
     `Plugins/BrevExamplePlugin` reference plugin, carry a package-local
     `Resources/Localizable.xcstrings` catalog and resolve literals with
     `bundle: .module`.

3. **Per-target conventions.**
   - **App targets** (`apps/macOS`, `apps/iOS`, `BrevShareExtension`):
     non-SwiftUI string sites (`NSAlert`, `NSSavePanel` /
     `NSOpenPanel`, `UILabel.text`, `UIButton` titles,
     `MailBackendError.backendSpecific(message:)`) use
     `String(localized: "...")` — no `bundle:` argument, since the
     main app bundle is the default and correct target. Existing
     SwiftUI `Text("literal")` call sites are left as-is; they already
     resolve against the main bundle and pick up extraction
     automatically once `SWIFT_EMIT_LOC_STRINGS` is on.
   - **SPM packages** (`BrevDesign`, `BrevBackend`, `BrevAI`,
     `BrevCalendar`, `BrevCrypto`, `BrevMail`, `BrevSettings`, and by extension any future
     package that gains user-visible strings): `Text("...", bundle:
     .module)` for SwiftUI, `String(localized: "...", bundle: .module)`
     for everything else (`LocalizedError.errorDescription`,
     `.accessibilityLabel`, disclosure/consent copy, validation
     messages). Each such package gets
     `Sources/<Package>/Resources/Localizable.xcstrings` and
     `resources: [.process("Resources")]` on its target in
     `Package.swift`.
   - Protocol strings, log lines, dictionary/UserDefaults keys,
     identifiers, MIME headers, ICS/CalDAV wire content, keyword
     heuristics, and test fixtures are deliberately **not** wrapped —
     these are not user-facing text and localizing them would change
     wire-format or storage-key behavior.

4. **Packages swept in the initial implementation:** `BrevDesign` (accessibility
   labels, preference titles/subtitles), `BrevBackend`
   (`LocalizedError.errorDescription` across IMAP/SMTP/OAuth/import-
   export error types, the offline-mutation-conflict summary text),
   `BrevAI` (AI Writer / Mailbox Assistant disclosure and consent
   copy, provider validation messages, `AIProviderKind` display
   names), and `BrevCalendar` (the CalDAV Keychain credential error
   descriptions). `BrevMail` now follows the same package convention: its
   100-call-site residual inventory is closed, its catalog contains the
   package-local keys, and non-localizable values are explicit verbatim text.
   `BrevSettings` retains its own catalog and is tracked as a separate
   conversion batch. The reference plugin and
   both iOS extensions are now covered by the same source-root enforcement;
   the notification-content extension remains catalog-free because it has no
   authored copy.

5. **No new abstraction.** This ADR does not introduce a
   localization helper type, a custom `Bundle` resolution shim, or a
   pseudo-localization test harness. `String(localized:)` /
   `Text(_:bundle:)` are Apple's supported mechanism and need no
   wrapper.

## Rationale

**Why String Catalogs over `.strings`/`.stringsdict` files.**
`.xcstrings` is Apple's current recommended format: Xcode extracts new
strings automatically on build, flags stale ones, and supports plural
variants and per-string comments in one file instead of one
`.strings` file per language per target. Hand-maintained `.strings`
files would require a separate extraction script and drift silently.

**Why `bundle: .module` only in packages, not apps.** App targets are
single-bundle: `String(localized:)` and `Text("...")` both default to
`Bundle.main`, which is correct there. SPM package targets each build
their own resource bundle; omitting `bundle: .module` in a package
would compile but resolve strings against whatever the *host* app's
main bundle happens to contain, silently falling back to the English
literal even after a translation is added. Making `.module` explicit
in packages avoids a class of "translation added, string still shows
in English" bugs that only surfaces once a second language exists.

**Why leave existing app-target `Text("literal")` untouched.** SwiftUI
`Text` already extracts and localizes correctly against `Bundle.main`
once `SWIFT_EMIT_LOC_STRINGS` is on — there is nothing to change.
Touching every `Text(...)` call site in the app targets for a no-op
conversion would be a large, low-value diff purely for the sake of
uniformity.

**Why no InfoPlist catalog for the notification-content extension.**
Its `Info.plist` only carries build-substituted values
(`CFBundleDisplayName` for the extension itself, no usage-description
strings) that are not surfaced to the user in a way distinguishable
from the host app's own display name; adding an empty catalog for it
would be dead infrastructure.

**Alternatives considered.**

- *Localize now, in this same change.* Rejected — translating ~250
  strings across five packages and two apps needs native-speaker
  review this change doesn't have. Infra first, translations as a
  follow-up PR per language.
- *A shared `BrevL10n` package exporting a typed string-key API
  generated from the catalogs (SwiftGen-style).* Rejected as
  premature: `String(localized:)` and `Text(_:bundle:)` are already
  plain Swift with no codegen step, and the string count so far (a few
  hundred, mostly short and static) doesn't justify generated
  accessors or an additional build-time codegen dependency.
- *One shared `Localizable.xcstrings` for all packages, referenced by
  path.* Rejected — SPM resource bundling is per-target; a shared
  catalog would need to live in a dedicated resource-only package
  that every consumer depends on, adding a package and a dependency
  edge for no benefit over one small catalog per package.

## Consequences

### Accepted

- Each app, extension, converted package, and user-facing plugin owns a
  small `.xcstrings` file. Catalogs start with only English content and grow
  as translations are added; the notification-content extension has no
  catalog because it renders only payload-provided copy.
- `Package.swift` for each package with user-facing copy gains a
  `resources:` array; any future `swift build`/`swift test` picks up the
  resource-bundle step, adding a small amount of build time.
- Contributors adding new user-visible strings must follow the
  `bundle: .module` convention in packages (codified in `AGENTS.md`)
  or the string silently resolves against the wrong bundle once
  translations exist. No automated check to catch this exists in
  packages other than a `Text("literal")`-without-`bundle:` SwiftLint
  rule.
- No behavior or visible English text changed. Snapshot tests are
  unaffected; verified via full `swift test` runs on every touched
  package.

### Risks

- **SwiftLint rule false positives.** A custom rule flagging
  `Text("...")` without `bundle:` inside `packages/**` risks matching
  `Text(verbatim:)` or `Text(someVariable)` call sites incorrectly if
  the regex is too broad. Mitigated by scoping the rule to literal
  string arguments only and excluding `apps/**` (where no `bundle:`
  is expected).
- **Catalog merge conflicts.** `.xcstrings` is JSON; two branches
  adding strings to the same catalog will conflict at the JSON level
  more often than two `.strings` files would, since Xcode reformats
  and reorders on save. Mitigated by keeping catalogs one per
  package/target (already true) rather than one repo-wide catalog,
  which shrinks the blast radius of a conflict.
- **BrevMail residual inventory is closed.** The 2026-08-25 audit found 100
  bare `Text("…")` call sites in the package after excluding the existing
  bundled attachment-search string and two bullet separators. All 100 are
  now accounted for: 89 user-visible strings resolve through `bundle: .module`,
  and 11 non-localizable values use `Text(verbatim:)` (numeric counters,
  a message-address rendering, the Brev brand, and TLS protocol identifiers).
  The two bullet separators remain explicit `Text(verbatim:)` values as well.
  The SwiftLint package-bundle rule and its deterministic coverage fixture now
  include `packages/BrevMail/Sources`, so a new bare package `Text("…")` cannot
  regress silently.

## References

- ADR-0005: Enforcement and automation (protected-paths gate this ADR
  satisfies for `apps/*/Project.swift` and `BrevDesign`/`BrevAI`/
  `BrevCalendar` public API changes)
- ADR-0004: Build system and project layout
- Apple: "Localizing and varying text with a string catalog"
- `prompts/new-adr.md`
