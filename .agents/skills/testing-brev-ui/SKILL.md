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
