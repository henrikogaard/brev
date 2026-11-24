# Design System, Themes, Avatars & UI

> Consolidates former ADRs `0002`, `0003`, `0015`, `0017`, `0018`, `0019`, `0025`, `0033`, `0058`, and `0083`.

## Theme Token System (Hard Invariant)

All visual colors flow through `@Environment(\.brevTheme)` (`BrevTheme` in `packages/BrevThemes/`), never literal colors:

- **Hard rule (mechanically enforced by SwiftLint `no_literal_colors_in_views` and `scripts/privacy-audit.sh`):** No `Color.blue`, `Color(hex:)`, or `UIColor.*` literals in `apps/` or `packages/{BrevDesign,BrevMail,BrevSettings}/`. `Color.clear` is the only allowed structural exception.
- **Semantic tokens:** Surfaces (`bgPrimary`, `bgSecondary`, `bgTertiary`), text (`textPrimary`, `textSecondary`, `textTertiary`), accents & status (`accent`, `accentMuted`, `success`, `warning`, `danger`, `info`), structure (`border`, `separator`, `selection`), and `avatarPalette`.
- **Built-in & custom themes:** Ships IDE-inspired and monochrome light/dark theme pairs plus JSON user themes in `themes/`, independent light/dark pairing, and configurable application accent color. Sheets and panels apply `.brevSheetAppearance(theme)`.
- **Window materials (macOS):** Optional window translucency (`Off`, `Sidebars only`, `Full windows`) with live opacity controls and strict respect for macOS `Reduce Transparency` (solid surfaces when enabled).

## Sender Avatars (Relaxed from Former ADR-0003)

- Cascading resolution chain in `packages/BrevAvatars/`: **Apple Contacts (opt-in) → in-memory cache → BIMI → Domain favicon → Gravatar → themed initials**.
- **SVG safety:** BIMI SVG payloads referencing external images/stylesheets are rejected before rendering so an avatar fetch can never leak secondary requests.
- **Relaxed default posture:** Keep **Gravatar** (which hashes sender email addresses to a third party) strictly opt-in, and surface clear first-run opt-in toggles in the **Privacy & Convenience Choices** walkthrough (re-openable anytime from **Settings → Privacy & Security → Privacy → Review Privacy & Convenience Choices…**) separating domain-only **BIMI / Domain favicons** from **Gravatar** so users can opt into richer sender logos without flipping any zero-network default silently.

## Multi-Source Workspace & Platform Ergonomics

- **Multi-source mail workspace:** Unified Inbox and per-account navigation over multiple heterogeneous backends, with source-owned operations, local Profiles (filtering visible accounts without signing out), Favourites above collapsible accounts, capability-gated sidebar folder context actions (create/rename/delete/empty trash), and provider-agnostic colored flags (`orange`, `red`, `purple`, `blue`, `yellow`, `green`, `gray`).
- **macOS native craft:** Three-column layout, native menu bar and `NSToolbar`, single-key shortcuts (`J`/`K`, `E`, `H`, `R`), `⌘K` command palette, sequential Triage mode, detached reader/compose windows, and Apple Mail pointer-vs-keyboard focus semantics.
- **iPad & iPhone native craft:** Multi-window/auxiliary scene support on iPad (`UIWindowScene`), compact stacked reader and native sheets on iPhone, and Dynamic Type bounds on dense mail chrome so controls stay reachable and readable at accessibility text sizes without clipping.

## Home-Screen Widgets (`BrevWidgets`)

- `BrevMacWidgets` and `BrevMailWidgets` depend **only** on the lightweight `BrevWidgets` package—never `BrevBackend`, Realm, SQLite, or the network.
- The main app writes a sanitized, bounded JSON snapshot file into the shared App Group container (excluding sign-in codes and sensitive bodies); widgets render purely from that snapshot.

## Localization (`en` & `nb`)

- Every user-visible string uses Xcode String Catalogs (`Localizable.xcstrings`): `String(localized:)` / `Text(_:)` in app targets and `String(localized:bundle:.module)` / `Text(_:bundle:.module)` in SPM packages.
- Bare string literals in `Text`, `NSAlert`, `LocalizedError.errorDescription`, or accessibility labels are prohibited. Every shipped key carries both English (`en`) and Norwegian Bokmål (`nb`) translations without xcstringstool symbol collisions.
