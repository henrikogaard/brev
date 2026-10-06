---
name: testing-brev-ui
description: How to drive Brev's macOS app and iOS simulator for UI/UX testing — Command-key input workaround, simctl screenshots, simulator window management, and AX menu inspection.
---

# Testing Brev UI on macOS + iOS simulator

## Command-key shortcuts on macOS

The `key` action with the `super` modifier does NOT send ⌘ — it types a literal character. Use `cmd`/`command` in the key string instead (e.g. `key: "cmd+s"`), which does reach the app as a real ⌘ event (verified: ⌘S flagged/unflagged a selected message). If `cmd` ever fails, fall back to osascript System Events:

```bash
osascript -e 'tell application "System Events" to keystroke "," using command down'   # ⌘,
osascript -e 'tell application "System Events" to keystroke "n" using command down'   # ⌘N
osascript -e 'tell application "System Events" to keystroke "w" using command down'   # ⌘W close window
osascript -e 'tell application "System Events" to keystroke "/" using command down'   # ⌘/ shortcuts help
```

## iOS simulator

Screenshots (clean, no window juggling needed):
```bash
xcrun simctl io <udid> screenshot /tmp/shot.png
```

Multiple simulators may be booted — raise the correct one (match UDID → iOS version in the window title):
```bash
osascript <<'EOF'
tell application "System Events"
  tell process "Simulator"
    set frontmost to true
    perform action "AXRaise" of window "iPhone 17 – iOS 27.0"
    set position of window "iPhone 17 – iOS 27.0" to {420, 30}
  end tell
end tell
EOF
```

Interact by clicking the simulator window's content area (taps = clicks, swipe = left_click_drag, long-press = left_mouse_down + wait + left_mouse_up — left_mouse_down takes NO coordinate arg; mouse_move first).

Gotchas:
- `simctl io screenshot` PNG pixel coordinates do NOT match on-screen window coordinates — tap using window position from a `computer` screenshot, never the PNG's pixels.
- Keep the sim window clear of overlapping app windows (AXRaise + reposition it before driving).
- Stray clicks near screen edges can trigger system dialogs (a logout confirmation appeared once) — cancel them promptly.
- The host display is 1600×1200 logical points — `computer` tool coordinates are ×1.5625 physical pixels; divide measured px by 1.5625 to get pt sizes (e.g. a 143.6px rail ≈ 92pt).

Device logs: `xcrun simctl spawn <udid> log show --last 3m --predicate 'process == "BrevIOS"' --style compact`

## Inspecting the iOS app's accessibility tree

The `computer` tool's `inspect`/`query` on target `ios` often fails with "Failed to get frontmost application" (it binds to the first booted simulator and can miss the app even when it's foregrounded — `xcrun simctl shutdown <other-udid>` to leave only the target booted, or skip it entirely).

Reliable path — macOS Accessibility Inspector (`/Applications/Xcode-*.app/Contents/Applications/Accessibility Inspector.app`):
1. Open it, click the target pill in its toolbar → hover **Simulator** → pick the app process (e.g. "Brev (PID)"). Sim apps run as host processes and expose their full UIAccessibility tree.
2. Toggle the inspection pointer with the crosshair button (top-left of the inspector pane) or `osascript -e 'tell application "System Events" to key code 49 using {control down}'` (⌃Space).
3. Hover any sim control → the inspector shows Label / Value / Traits / Identifier / Actions (this is the "AX dump" evidence for accessibility acceptance checks).
4. **While point-inspection is on, taps on the sim only inspect — they never activate.** Toggle it off to tap, or better: click the **Perform** button next to an action (e.g. Activate) in the inspector to invoke the element directly — reliable navigation without mouse taps.
5. Note the element field line reads `Label, Role` (e.g. `Refresh, Button`) — non-empty Label + Button trait means VoiceOver announces name+role correctly.

## Menu-bar audit without flaky clicks

Menu clicks through the `computer` tool are racy. Enumerate menus reliably via accessibility:

```bash
osascript <<'EOF'
tell application "System Events"
  tell (first process whose name contains "Brev Test")
    repeat with m in (menu bar items of menu bar 1)
      log (name of m)
      try
        log (name of every menu item of menu 1 of m)
      end try
    end repeat
  end tell
end tell
EOF
```

This is also how you find empty menus and duplicated items without opening each one visually.

## Relaunching the macOS test app

```bash
BREV_USE_MOCK=1 "<DerivedData>/Brev Test (YYYY-MM-DD).app/Contents/MacOS/Brev Test (YYYY-MM-DD)" -ApplePersistenceIgnoreState YES &
```
Mock state is in-memory — relaunch re-seeds all messages/flags.

## Local PIM testing — the stub DAV server

Calendar/Contacts/Tasks surfaces need a real DAV source; `scripts/stub-dav-server.py` fakes one locally (PROPFIND discovery + REPORT + PUT/DELETE with etag preconditions; `--log` prints every request so you can verify writes).

```bash
mkdir -p /tmp/dav-seed   # create .ics (VEVENT/VTODO) + .vcf seeds — see scripts/stub-dav-server.py header
python3 scripts/stub-dav-server.py --port 8643 --seed /tmp/dav-seed --log /tmp/dav.log &
```

Connect in-app: Settings → Calendar & Contacts → Add DAV Source… → pick kind (Calendar (CalDAV) / Contacts (CardDAV) / Tasks (CalDAV) — **a Tasks source is a separate kind even though VTODOs share the calendar collection**) → "Manual server URL" → `http://localhost:8643` + any creds → Connect. Then per-source "Editing" toggle gates write affordances, "⋯" menu has Sync Now. Re-open an already-open PIM window after connecting/toggling — it doesn't live-refresh.

iOS caveat: each Connect triggers the system "Save Password?" sheet which blocks the AX tree — dismiss with "Not Now" before continuing.

`simctl ui <udid> content_size accessibility-extra-large` sets Dynamic Type without touching Settings UI (reset with `content_size large`).

## DAV write verification

Every UI write should appear in the stub log: edit → `PUT <stored-href> cond="etag"`, create → `PUT <new-uid>-brev.ics cond=*`, delete → `DELETE`, task complete → `PUT` on the VTODO. No request in the log = the write never left the app.

## Seeding PIM sources into the iOS simulator

`hasSources` only checks for a sources record — copy the macOS session's `pim-sources.json` into the sim container instead of re-connecting through the UI:

```bash
SIM_CONTAINER=$(xcrun simctl get_app_container <udid> eu.brevmail.brev.test data)
mkdir -p "$SIM_CONTAINER/Library/Application Support/Brev"
cp "$HOME/Library/Application Support/Brev/pim-sources.json" "$SIM_CONTAINER/Library/Application Support/Brev/"
```

Relaunch the app — PIM surfaces treat it as a connected source.

## Rebuilding + launching the iOS app in mock mode

The default `/Applications/Xcode.app` (26.x) resolves **no** iOS-simulator destinations for this repo's scheme (`xcodebuild` errors "iOS 26.5 is not installed"). iOS 27 sims only resolve under Xcode 27:

```bash
DEVELOPER_DIR=/Applications/Xcode-27.0-RC.app/Contents/Developer \
  xcodebuild -workspace Brev.xcworkspace -scheme BrevIOS -configuration Debug \
  -destination 'platform=iOS Simulator,id=<udid>' \
  -derivedDataPath <dd-path> -skipMacroValidation build

xcrun simctl install <udid> <dd-path>/Build/Products/Debug-iphonesimulator/BrevIOS.app
SIMCTL_CHILD_BREV_USE_MOCK=1 xcrun simctl launch <udid> eu.brevmail.brev.ios
```

`simctl openurl <udid> "mailto:a@b.co?subject=S&body=B"` routes straight into the app and presents the compose sheet (no "Open?" confirmation on iOS 27). Note `consumePendingComposePrefill` ignores a fully-empty `mailto:` — for an empty-recipient compose use the pencil FAB or remove the prefilled chip instead.

## Verifying text colors / rotation / Dynamic Type on iOS

- Pixel-sample a simctl PNG to prove enabled/disabled color states (e.g. accent vs gray Send): a ~15-line Swift script over `NSBitmapImageRep.colorAt(x:y:)` beats eyeballing — `xcrun swift /tmp/sample.swift shot.png x1 y1 x2 y2` printing the darkest pixel of the region.
- Rotate a specific device: AXRaise its window first, then `click menu item "Rotate Right" of menu 1 of menu bar item "Device" of menu bar 1` on process "Simulator" (Device menu acts on the frontmost window).
- `xcrun simctl ui <udid> content_size accessibility-extra-large` exercises the `compactIOSAccessibility` compose variant; reset with `content_size large`.
- iOS bottom-anchored menus render bottom-up: the first logical item (e.g. "Bold") is the LOWEST menu row — tap near the bar, not the top of the popup.

## Focus-state verification caveat

`@FocusState` / `.focusSection()` focus does not appear in the AX tree — AX reads report nothing about which column holds keyboard focus. Verify focus rings visually in screenshots (the accent column-border outline), and drive the ring deterministically.

Pointer→focus claims are ASYMMETRIC on macOS (Apple Mail's pointer≠keyboard-focus model):
- Clicking a message row DOES claim list keyboard focus (`selectMessage` sets `listKeyboardFocus`) — ring appears on the list column, ↑/↓ then move message selection.
- Clicking a mailbox row does NOT claim sidebar focus — it only selects the mailbox; the previously-focused column keeps the ring and your next arrow key goes there (easy to misread as "sidebar focus didn't move"). To focus the sidebar, press **Tab** (cycles into the sidebar's focus scope → ring on the column) or an arrow while it already holds focus.
- Mailbox-activation hand-off: with the sidebar focused, **Return** on a highlighted mailbox/folder — or **→** on a leaf (non-expandable) folder — hands focus to the list column; **Return/→** on the Outbox row instead opens the outbox presentation.
- The Outbox sidebar row only renders when `outboxPendingCount > 0` (queued mutations + scheduled sends); MockBackend implements neither `OutboxManaging` nor `ScheduledSendManaging`, so the row never appears in mock — verify its keyboard path in code or on a real/offline session.

## ⌘W leaves the process alive

Closing the last macOS window keeps the app running. Reopen the window with AppleScript instead of relaunching:

```bash
osascript -e 'tell application "Brev Test (YYYY-MM-DD)" to reopen'
```

## Forcing the onboarding LoginView on iOS

DEBUG builds auto-seed the demo account via `DeveloperSettings.isDemoModeRequested` — persisted in UserDefaults/app-group, so a plain `simctl launch` (and even uninstall+reinstall in some cases) still lands in the Inbox. Force onboarding with an explicit zero override:

```bash
SIMCTL_CHILD_BREV_USE_MOCK=0 xcrun simctl launch <udid> eu.brevmail.brev.ios
```

If demo content still appears, `xcrun simctl uninstall <udid> eu.brevmail.brev.ios` + reinstall + relaunch with `BREV_USE_MOCK=0` (the app-group store may survive uninstall). Settings → Accounts → ⓘ → Remove alone does NOT reliably clear it.

## iOS OAuth client IDs are xcodebuild overrides, not tuist-generate env

`tuist generate` leaves `BREV_GOOGLE_OAUTH_IOS_CLIENT_ID = ""` in the pbxproj **by design** (script/build_and_run.sh comment: generated project must not keep a stale OAuth value). Verified: `mise exec -- tuist generate` with the env var set still bakes empty. The real injection is build-time via `build_and_run.sh` → xcodebuild overrides → Info.plist `BREVGoogleOAuthIOSClientID`:

```bash
IOS_ID="$BREV_GOOGLE_OAUTH_IOS_CLIENT_ID"   # bind secret via exec env
IOS_SCHEME=$(printf '%s' "$IOS_ID" | awk -F. '{for(i=NF;i>0;i--)printf "%s%s",$i,(i>1?".":"")}')
xcodebuild ... build \
  "BREV_GOOGLE_OAUTH_IOS_CLIENT_ID=$IOS_ID" \
  "BREV_GOOGLE_OAUTH_IOS_CALLBACK_SCHEME=$IOS_SCHEME" \
  "BREV_GOOGLE_OAUTH_IOS_REDIRECT_URI=$IOS_SCHEME:/oauth2redirect"
# verify: PlistBuddy -c "Print :BREVGoogleOAuthIOSClientID" <app>/Info.plist | wc -c
```

Caveat: xcodebuild echoes command-line build settings into its log header — the client ID value gets printed there (it's a non-confidential public OAuth ID, but don't grep-and-paste logs around it). "Continue with Google" on LoginView needs clientID + scheme==reversed(clientID) + redirectURI=`scheme:/oauth2redirect` (GoogleOAuthPlatformConfiguration.isValid).

Fresh worktrees need `mise exec -- tuist install` before `tuist generate` ("We could not find external dependencies" otherwise).

## DAV connect-error classification gotcha (iOS)

`stub-dav-server.py --auth u:p` answers wrong creds with `401` **plus** `WWW-Authenticate: Basic` — iOS URLSession then surfaces a transport-level error (likely `NSURLErrorUserCancelledAuthentication`), which `PIMDAVClient.mapTransportError` maps to `transportFailed` ("The server could not be reached") instead of `authenticationRequired` ("The server rejected these credentials"). A bare `401` without the challenge header produces the correct credentials-rejected message — verified by A/B against a trivial `send_response(401)` python server. When verifying DAV auth errors, check WHICH 401 shape the test server emits before trusting the callout text.

## iOS mail account setup failure on unsigned sims

`Add account` in IMAPAccountSetupSheet fails fast with a red in-sheet banner "Couldn't save the mail credential in Keychain" (Keychain -34018 on unsigned builds) — it does NOT hang on an unreachable host. That failure still sets `session.signInError`, so it's a valid trigger for sign-in-error UI paths. The failure banner renders at the BOTTOM of the sheet's scroll content — scroll down to see it.

## Simulating a dead TLS handshake (connect-timeout testing)

To verify request-timeout bounds (e.g. PIMDAV `requestTimeout`), point the app at a **silent TCP listener** — not a plain-HTTP stub. Python's `http.server` replies `400` to a TLS ClientHello in ~15ms, so `https://` fails instantly and never exercises the timeout. A socket that accepts and never responds does:

```python
import socket, threading, time
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 8643)); s.listen(5)
while True:
    c,_ = s.accept(); threading.Thread(target=lambda c=c: (time.sleep(300), c.close()), daemon=True).start()
```

Verify the stall with `time curl -sk -m 20 https://127.0.0.1:8643/` (must run the full 20s; `nc -l` does NOT work — macOS BSD nc closes on stdin EOF). Confirm the app connected via `lsof -i :8643`. To time the UI failure, note `date +%s` at Connect-tap and poll `simctl io … screenshot` every ~3s: the toolbar Connect button dims while `isConnecting` and re-enables when the request fails — on branches without the in-sheet callout (pre-D1), that clear is the only observable.

### iOS sheet field taps (DAV connect sheet)

In `PIMSourceConnectSheet`, field-box centers sit noticeably ABOVE where the placeholder text visually reads: with sheet top at ~y140, Server URL box ≈y307-319, Username ≈y428, App-password ≈y463 — a tap ~20px low lands between fields and typed text goes to the previously focused field. Verify each field's content in a screenshot after typing.

## Mock-mode DAV credentials are session-scoped (relaunch wipes them)

Under `BREV_USE_MOCK=1`, `AppSessionFactory` wires `InMemoryCalDAVCredentialStore` — staged DAV credentials live in memory only for the app process. If the app relaunches mid-test (even without reinstall), connected DAV sources lose their credential: sync and writes then fail with "The source has no stored credential. Reconnect it first." and the source row flips to `Failed — missingCredential`. This is an environment artifact, not a product bug. Recovery that preserves cached records: Settings → Calendar & Contacts → source row `…` menu → **Reconnect…** → re-enter creds → Ready again (deleting+re-adding the source also works but drops cached event records and their record IDs). Avoid relaunching after connecting if your test needs writes.

## `ios` AX target + multi-sim caveat

The `computer` `ios` accessibility target binds the FIRST booted simulator. If several sims are booted, `xcrun simctl shutdown` the extras — the target then binds the right one and gives reliable `press`/`set_text`/`scroll_to` (far better than coordinate taps, and SwiftUI Toggle shows as role=checkbox "Editing for <source>" etc.). Detail-pane action rows (Edit/Delete) may be absent from the AX tree in portrait but appear after rotation or on re-render.

## Calendar editor conflict copy location

`CalendarEventEditorView` renders `editing.lastError` as red caption text at the BOTTOM of the form (after Notes) — below the fold, so scroll the sheet to see it. The same error propagates to the leading-column banner in `CalendarRootView` when the sheet dismisses. Verifying "This event changed on the server. Sync, then try again." requires scrolling the open editor, not just looking at the top fields.

## Contacts/Tasks covers: sync affordance + row-tap gotcha

Contacts and Tasks covers (sidebar → More) each have a circular sync button at the top-right of the cover nav bar — tapping it fires a DAV REPORT that merges remote bumps into cache (pull-to-refresh on the lists does NOT trigger a DAV sync). On a non-maximized sim window the button sits partly clipped at the top edge but remains tappable. Conflict errors from editors propagate to a banner at the top of the Contacts/Tasks list on dismiss.

Caution on the Tasks list: each row's AX node is a "Mark as completed, <title>" button — an AX `press` toggles completion instead of opening detail. Tap the row's title text by coordinates to open TaskDetailView, then use the "Edit task"/"Delete task" buttons.

## Settings sheet: use Search Settings to reach Calendar & Contacts

The iOS Settings sheet is a long scrollable list (App → Reading & Composing → Organization → …). "Calendar & Contacts" sits far down and coordinate drags often rubber-band back. Fast path: type `Calendar` in the "Search Settings" field at the bottom — results filter to the section's rows; tap one to open the section.

## Add DAV Source sheet — all three kinds work against one stub endpoint

The connect sheet's "Type" combobox offers Calendar (CalDAV) / Contacts (CardDAV) / Tasks (CalDAV) — press it to open a context menu, then press the option. Tasks-kind sources discover the VTODO-capable /cal/ home set on the same stub endpoint (no separate tasks port needed). Fill Server URL first via set_text, then scroll down for Username/App-specific password/Display name — Connect enables once all are non-empty.

## Google PIM sources: collection discovery is a manual Settings action

Google Calendar/Contacts/Tasks sources sit in Settings → Calendar & Contacts. Key gotchas when testing them on the iOS sim (QA Google account):

- **"Sync calendars now" ≠ collection discovery.** Event/contact sync only pulls entities for already-discovered collections. Collections (calendarList.list, contactGroups) are discovered ONLY via the source row's `⋯` menu → **"Refresh Collections"** (explicit user action, no background traffic per ADR-0006). If a source shows "No collections discovered yet.", press Refresh Collections — that is also what surfaces the real Google error.
- **Discovery errors classify on the source row.** A 403 `accessNotConfigured`/`SERVICE_DISABLED` → `serviceDisabled` + banner "The Google API … is not enabled for Brev's sign-in project. Enable it in Google Cloud Console — reconnecting cannot fix this." (the API is off in the OAuth client's GCP project — Henrik-side, can't be fixed in-app). Any other 403 → `authenticationRequired` ("Google rejected the account's authorization"). Check which string the row shows before assuming the fix.
- **Write ops need "Allow editing".** The Calendar cover's `+` new-event button renders only `if editing.canAuthor && defaultTarget != nil` — gated by the "Allow editing" toggle on the source row, which runs `enableGooglePIMWriteFeature` → ASWebAuthenticationSession re-auth with the write scope. On the QA account Google may SMS-challenge a fresh device fingerprint on Henrik's phone (+47 …55); it returns "Google har ikke bekreftet appen" → tap "Avansert" → "Gå til Brev (utrygt)" → "Fortsett" (scroll the consent page for the button). A second re-auth shortly after often skips the SMS (session cookie).
- **No `+` = no writable collection.** Even with "Allow editing" ON, `+` stays hidden until ≥1 writable collection is discovered — so enable editing, then Refresh Collections. A `serviceDisabled` source never reaches a writable target.
- **Failed sources hide create UI (correct):** a source at `Failed`/`authenticationRequired` gives `editing.canEdit=false` → its cover shows "No contacts/events" with no create button and no Allow-editing toggle — capability-driven UI, not a bug.
- **Preflight for Henrik:** if a Google PIM source reports `serviceDisabled`, the fix is enabling Google Calendar / People / Tasks APIs in the OAuth client's GCP project (client id `879180545678-…`) — it is NOT an OAuth/grant problem, so don't re-run sign-in expecting it to resolve.

## Locale testing (nb / non-English)

`String(localized:)` catalogs can be exercised without touching the system language:

**macOS** — relaunch the dated test build with `-AppleLanguages` (build via `script/build_and_run.sh --mock` first, quit it, then relaunch):

```bash
BREV_USE_MOCK=1 "<DerivedData>/Brev Test (YYYY-MM-DD).app/Contents/MacOS/Brev Test (YYYY-MM-DD)" \
  -ApplePersistenceIgnoreState YES -AppleLanguages "(nb)" &
```

Use `(en)` for an English baseline on the same build — the broken-state comparison costs one relaunch.

**iOS** — pass the arg through `simctl launch`:

```bash
SIMCTL_CHILD_BREV_USE_MOCK=1 xcrun simctl launch <udid> eu.brevmail.brev.ios -AppleLanguages "(nb)"
```

## Verifying translations

- Interpolated strings (`%lld`/`%@` keys) are the ones that silently fall back to English when a catalog key is wrong — prefer them over static strings when checking a l10n change. The folder-stats footer ("N meldinger · M uleste" nb) is always visible at the bottom of the macOS message list and uses three interpolated keys.
- macOS toolbar Menu buttons are icon-only; their `.help` tooltip == the accessibility label — hover the button to read localized AX copy without VoiceOver, or query it via osascript System Events.
- The thread "N hidden read messages" footer needs `Kun uleste` (Unread only) active AND at least one read message in the thread — mark a card read via its right-click context menu to force it.
- iOS: the `ios` AX target reads the sim's full tree (button labels like "Sorter og filtrer, sortert nyeste først" appear in nb); the folder-stats footer does NOT render on the iOS list — verify counts via section-header AX labels ("I dag, 3 meldinger, utvidet") or the toolbar filter label instead.
- xcstringstool symbol collisions: two catalog keys that differ only by case (or produce the same `word(_:)` signature, e.g. `Foo %@` vs `foo %@`) hard-fail at build time. Fast pre-build check: normalize keys to camelCase + arity and look for duplicates — the `no two catalog keys generate the same symbol` guards in `MailStatusCopyLocalizationTests`/`BackendCatalogKeyFormatTests` encode this.
