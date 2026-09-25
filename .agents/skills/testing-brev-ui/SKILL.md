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
