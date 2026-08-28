# Settings Inventory

Last updated: 2026-05-31

This inventory records the v1 settings models and their persistence
owner. The goal is to keep the settings surface intentional: views
should use typed models through `SettingsPersistenceStore` instead of
scattering raw `UserDefaults` keys through panels.

## BrevSettings

| Area | Model / helper | Storage owner | Notes |
| --- | --- | --- | --- |
| Accounts | `AccountStore` | `BrevBackend` | Apps inject the store; `BrevSettings` only reads account values and calls add/sign-out closures. |
| Appearance themes | `AppearanceThemeSettings` | `SettingsPersistenceStore` | Shared by apps to resolve the active light/dark theme pair. |
| App icons | `AppIconPreferences` / `AppIconVariant` | `SettingsPersistenceStore` | Apps apply the platform-specific icon change. |
| Window materials / chrome | `WindowAppearancePreferences`, `WindowTranslucencyMode`, `WindowTranslucencyScope`, `WindowSurfaceRole` | `SettingsPersistenceStore` via `BrevDesign` preference keys | Frozen/protected by ADR-0015. This inventory documents the implemented Appearance controls only: mode, scope, pane opacity, and sidebar opacity. Do not expand this into new window material behavior without the governing ADR changing first. |
| Mailbox view | `MailboxViewSettings` | `SettingsPersistenceStore` | Uses `MailboxViewPreferenceKey` from `BrevDesign` so mail views and Settings share keys, including sender icons, preview lines, and the folder stats footer. |
| Avatar privacy | `AvatarPrivacySettings` | `SettingsPersistenceStore` | External avatar sources remain off by default per ADR-0006. |
| Remote content allowlist | `RemoteContentPolicy` | `SettingsPersistenceStore` | Local JSON allowlist for senders/domains. |
| Browser | `BrowserSettings`, `BrowserChoice`, `BrowserLinkOpener` | `SettingsPersistenceStore` / `UserDefaults` key `browser.preferredBrowser` | Shipped in Privacy. Default is `.systemDefault`; choices are system default, Safari, Chrome, Firefox, Edge, and Brave. The app shell injects `BrowserLinkOpener` into SwiftUI `openURL` so message, about, and settings links use the saved preference. Scoped browser keys exist for tests/profile-specific callers, but the shipped app path uses the global key. |
| Compose | `ComposeSettings` | `SettingsPersistenceStore` | Local defaults only; send-pipeline enforcement lands in separate issues. |
| Signatures | `SignatureSettings` | `SettingsPersistenceStore` | Local default and per-account signature model. |
| Notifications | `NotificationSettings` | `SettingsPersistenceStore` | Local notification preferences; closed-app delivery is best effort. |
| Updates | `UpdateSettings`, `UpdateCheckCadence`, `UpdateChannel`, `UpdateBuildConfiguration`, `SettingsUpdateActions` | `SettingsPersistenceStore` / `UserDefaults` keys `updates.cadence`, `updates.channel` | Capability-gated. Visible for macOS direct-download builds via `SettingsSectionAvailability.macOSDirectDownload`; hidden from `v1Default`. Defaults are once-per-launch checks and the stable appcast. Sparkle initialization/manual checks require macOS, direct-download distribution, a feed URL, and a configured public EdDSA key. Update checks contact `updates.brevmail.eu` only for direct-download macOS builds. |
| Fetch schedule | `FetchScheduleSettings`, `FetchInterval` | Local `UserDefaults` keys `fetch.interval`, `fetch.backgroundEnabled` | Implemented internal model. Defaults to manual fetch with background fetch enabled. Supported intervals are manual, 5 minutes, 15 minutes, 30 minutes, and 1 hour; invalid persisted values fall back to defaults. Not exposed as a shipped top-level Settings section in the current inventory. |
| AI Writer | `AIWriterSettings` | `SettingsPersistenceStore` | Consent and enablement are explicit local flags. |
| Advanced | `AdvancedSettings` | `SettingsPersistenceStore` | Hidden until storage/import/export work is ready. |
| Smart mailboxes | `SmartMailboxSettings` | `SettingsPersistenceStore` | Hidden model work for future sidebar/search views. |
| Folders | `FolderPreferences` | `SettingsPersistenceStore` | Preferences only; backend move/archive behavior remains separate. |
| BYOK AI | `BYOKAISettings` | `SettingsPersistenceStore` | Feature-gated v2 settings surface; tracks enablement and legacy defaults (`openai`, `ollama`, or custom). |
| AI provider configurations (v2) | `AIProviderConfigurationStore`, `AIProviderAccountAssignmentStore`, `AIProviderSettingsPersistence` | `SettingsPersistenceStore` | Stores provider metadata per-account/source (`displayName`, endpoint URL, `modelID`, kind, enabled/default flags). |
| AI provider API keys | `AIProviderKeychainSecretStore` | OS Keychain | Hostnames and model metadata stay in settings storage; API keys remain in Keychain and are deleted when a provider configuration is removed. |
| CalDAV | `CalDAVSettings` | `SettingsPersistenceStore` | Future write target configuration; hidden until feature-gated. |
| Encryption | `EncryptionSettings` | `SettingsPersistenceStore` | Future OpenPGP/S/MIME preferences; hidden until feature-gated. |
| Out of office / forwarding | `OutOfOfficeSettings`, `ForwardingSettings` | `SettingsPersistenceStore` | Preference models only; backend support is out of scope for #16. |

## BrevMail Compatibility

| Helper | Why it remains |
| --- | --- |
| `ThemePreferences` | Compatibility fallback for the older single-theme key while apps migrate to `AppearanceThemeSettings`. |
| `AvatarPreferencesBootstrap` | Startup bridge that copies saved avatar toggles into `AvatarResolver` before settings UI opens. |
| `MailboxViewPreferenceKey` usage through `@AppStorage` | Mail list/detail views need live SwiftUI bindings for shared mailbox rendering preferences. Keys are owned by `BrevDesign` and configured by `BrevSettings`. |
| `MailProfileStorage` | Profile filtering is mailbox workspace state, not a global app settings section. |
| `BrevMail.SettingsView` | Legacy/fallback in-mail quick sheet when an embedding app does not provide `onOpenSettings`; app targets now open `BrevSettings.SettingsView`. |

## Section Availability

`SettingsSection.availability` is the source of truth for whether a
section is shipped, capability-gated, feature-flagged, or hidden as
roadmap-only. `SettingsSectionAvailability.v1Default` exposes only
`.shipped` sections.
