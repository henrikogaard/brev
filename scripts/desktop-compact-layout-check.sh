#!/usr/bin/env bash
# Verifies Brev's compact desktop window contract without live OAuth.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Brev"
WIDTH="${BREV_COMPACT_WINDOW_WIDTH:-960}"
HEIGHT="${BREV_COMPACT_WINDOW_HEIGHT:-600}"
MAX_CHROME_DELTA="${BREV_COMPACT_WINDOW_MAX_CHROME_DELTA:-96}"
SOURCE_FILE="$ROOT/apps/macOS/Sources/BrevApp.swift"
MAIL_ROOT_FILE="$ROOT/packages/BrevMail/Sources/BrevMail/BrevMailRootView.swift"
MAIL_PANE_SURFACE_FILE="$ROOT/packages/BrevMail/Sources/BrevMail/MailPaneSurface.swift"
COMPOSE_FILE="$ROOT/packages/BrevMail/Sources/BrevMail/ComposeView.swift"
COMPOSE_POLICY_FILE="$ROOT/packages/BrevMail/Sources/BrevMail/ComposePresentation.swift"
SETTINGS_FILE="$ROOT/packages/BrevSettings/Sources/BrevSettings/SettingsView.swift"
RUN_RUNTIME=0
SCREENSHOT_PATH=""

require_file() {
  local path="$1"
  local description="$2"
  if [[ ! -f "$path" ]]; then
    echo "error: missing $description: $path" >&2
    exit 1
  fi
}

require_pattern() {
  local pattern="$1"
  local path="$2"
  local message="$3"
  if ! rg -q "$pattern" "$path"; then
    echo "error: $message" >&2
    echo "       checked: ${path#$ROOT/}" >&2
    exit 1
  fi
}

require_multiline_pattern() {
  local pattern="$1"
  local path="$2"
  local message="$3"
  if ! rg -U -q "$pattern" "$path"; then
    echo "error: $message" >&2
    echo "       checked: ${path#$ROOT/}" >&2
    exit 1
  fi
}

require_fit() {
  local label="$1"
  local required="$2"
  local available="$3"
  if (( required > available )); then
    echo "error: $label requires ${required}px, exceeding ${available}px compact contract" >&2
    exit 1
  fi
}

usage() {
  echo "usage: $0 [--runtime] [--screenshot /absolute/path.png]" >&2
  echo "       defaults to a static source-contract check for ${WIDTH}x${HEIGHT}" >&2
}

windowserver_brev_window_info() {
  /usr/bin/swift - "$APP_NAME" <<'SWIFT'
import CoreGraphics
import Foundation

let appName = CommandLine.arguments.dropFirst().first ?? "Brev"
let windows = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements],
    kCGNullWindowID
) as? [[String: Any]] ?? []

for window in windows {
    guard (window[kCGWindowOwnerName as String] as? String) == appName,
          let number = window[kCGWindowNumber as String] as? Int,
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let width = bounds["Width"] as? Int,
          let height = bounds["Height"] as? Int,
          let x = bounds["X"] as? Int,
          let y = bounds["Y"] as? Int else {
        continue
    }
    let name = (window[kCGWindowName as String] as? String) ?? ""
    print("\(number)\t\(width)\t\(height)\t\(x)\t\(y)\t\(name)")
    exit(0)
}

exit(1)
SWIFT
}

runtime_app_name() {
  local test_date="${BREV_TEST_DATE:-$(date +%F)}"
  local search_root candidate
  local expected_bundle="Brev Test (${test_date}).app"

  # The default build identity is intentionally dated and must not be
  # confused with the daily-driver Brev.app. Discover the actual bundle that
  # build_and_run.sh produced before asking AppKit/System Events for windows.
  for search_root in \
    "$ROOT/.codex/build/macos/DerivedData/Build/Products/Debug" \
    "${BREV_INSTALL_DIR:-/Applications}"; do
    [[ -d "$search_root" ]] || continue
    candidate="$(find "$search_root" -maxdepth 1 -type d -name "$expected_bundle" -print -quit)"
    if [[ -n "$candidate" ]]; then
      basename "${candidate%.app}"
      return 0
    fi
  done

  echo "error: could not discover runtime app bundle $expected_bundle" >&2
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runtime)
      RUN_RUNTIME=1
      shift
      ;;
    --screenshot)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "error: --screenshot requires a path" >&2
        usage
        exit 2
      fi
      SCREENSHOT_PATH="$2"
      RUN_RUNTIME=1
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

require_file "$SOURCE_FILE" "macOS app source"
require_file "$MAIL_ROOT_FILE" "mail root source"
require_file "$MAIL_PANE_SURFACE_FILE" "mail pane layout policy source"
require_file "$COMPOSE_FILE" "compose source"
require_file "$SETTINGS_FILE" "settings source"

echo "==> compact window source contract"
require_pattern "\\.frame\\(minWidth: ${WIDTH}, minHeight: ${HEIGHT}\\)" \
  "$SOURCE_FILE" \
  "expected BrevMailRootView to keep a ${WIDTH}x${HEIGHT} minimum frame"
require_multiline_pattern "LoginView\\(session: session\\)[[:space:]]*\\n[[:space:]]*\\.frame\\(minWidth: ${WIDTH}, minHeight: ${HEIGHT}\\)" \
  "$SOURCE_FILE" \
  "expected LoginView to share the ${WIDTH}x${HEIGHT} minimum frame so account restore does not resize the window"
echo "    OK (${WIDTH}x${HEIGHT})"

echo "==> main window titlebar contract"
require_pattern "\\.brevHiddenWindowTitle\\(\\)" \
  "$SOURCE_FILE" \
  "expected the main window to apply the shared hidden-title modifier"
require_pattern "toolbar\\(removing: \\.title\\)" \
  "$SOURCE_FILE" \
  "expected macOS 15 and newer to use SwiftUI's native title-toolbar removal"
require_pattern "titleVisibility = \\.hidden" \
  "$SOURCE_FILE" \
  "expected macOS 14 to hide the title through the narrow AppKit window bridge"
require_multiline_pattern "\\.brevWindowTranslucency\\(windowRole: \\.settings\\)[[:space:]]*\\n[[:space:]]*\\.brevTransparentWindowToolbarBackground\\(\\)[[:space:]]*\\n[[:space:]]*\\.brevHiddenWindowTitle\\(\\)" \
  "$SOURCE_FILE" \
  "expected Settings to use the shared transparent, title-free window chrome"
echo "    OK (native title removal with macOS 14 fallback)"

echo "==> mail root pane contract"
require_multiline_pattern "static func folderSidebar\\(platform: MailPanePlatform\\)[[:space:]]*->[[:space:]]*MailPaneColumnWidth\\?[[:space:]]*\\{[[:space:]]*switch platform" \
  "$MAIL_PANE_SURFACE_FILE" \
  "expected sidebar layout policy to keep a 200px compact minimum"
require_pattern "MailPaneColumnWidth\\(minimum: 200, ideal: 240" \
  "$MAIL_PANE_SURFACE_FILE" \
  "expected sidebar layout policy to keep a 200px compact minimum"
require_pattern "\\.frame\\(minWidth: 320, idealWidth: 420\\)" \
  "$MAIL_ROOT_FILE" \
  "expected message list to keep a 320px compact minimum"
require_pattern "static func readerMinimumWidth" \
  "$MAIL_PANE_SURFACE_FILE" \
  "expected reading pane policy to define a compact minimum"
require_multiline_pattern "case \\.macOS:[[:space:]]*420" \
  "$MAIL_PANE_SURFACE_FILE" \
  "expected reading pane detail to keep a 420px compact minimum"
mail_required_width=$((200 + 320 + 420))
require_fit "mail root panes" "$mail_required_width" "$WIDTH"
echo "    OK (${mail_required_width}px <= ${WIDTH}px)"

echo "==> compose compact contract"
# The 680x560 compact minimum moved from a literal frame in ComposeView into
# ComposeLayoutPolicy (ComposePresentation.swift); ComposeView applies it via
# frameMetrics. Verify both halves so the minimum can't silently regress.
require_pattern "\\.frame\\(minWidth: frameMetrics\\.minWidth, minHeight: frameMetrics\\.minHeight\\)" \
  "$COMPOSE_FILE" \
  "expected compose view to apply the policy-derived compact minimum frame"
require_pattern "ComposeFrameMetrics\\(minWidth: 680, minHeight: 560\\)" \
  "$COMPOSE_POLICY_FILE" \
  "expected ComposeLayoutPolicy to define a 680x560 desktop compact minimum"
require_fit "compose width" 680 "$WIDTH"
require_fit "compose height" 560 "$HEIGHT"
echo "    OK (680x560 <= ${WIDTH}x${HEIGHT})"

echo "==> settings compact contract"
require_pattern "\\.frame\\(minWidth: 190, idealWidth: 210\\)" \
  "$SETTINGS_FILE" \
  "expected settings sidebar to keep a 190px compact minimum"
require_pattern "\\.frame\\(minWidth: 620, idealWidth: 740, minHeight: 540\\)" \
  "$SETTINGS_FILE" \
  "expected settings detail pane to keep a 620x540 compact minimum"
require_pattern "\\.frame\\(minWidth: 860, minHeight: 600\\)" \
  "$SETTINGS_FILE" \
  "expected settings window to keep an 860x600 compact minimum"
settings_required_width=$((190 + 620))
require_fit "settings split panes" "$settings_required_width" 860
require_fit "settings window width" 860 "$WIDTH"
require_fit "settings window height" 600 "$HEIGHT"
echo "    OK (${settings_required_width}px <= 860px <= ${WIDTH}px)"

if [[ "$RUN_RUNTIME" -ne 1 ]]; then
  echo "desktop-compact-layout-check.sh: static OK"
  echo "next: run with --runtime for an AppKit resize/screenshot smoke pass"
  exit 0
fi

echo "==> mock app launch"
BREV_VERIFY_STABILITY_SECONDS="${BREV_VERIFY_STABILITY_SECONDS:-4}" \
  "$ROOT/script/build_and_run.sh" --mock --verify

if ! APP_NAME="$(runtime_app_name)"; then
  echo "       expected the dated test app produced by script/build_and_run.sh" >&2
  exit 1
fi
echo "    discovered runtime app: $APP_NAME"

echo "==> resize main window to ${WIDTH}x${HEIGHT} content contract"
set +e
resize_output="$(
  osascript <<APPLESCRIPT
tell application "$APP_NAME" to activate
delay 0.5
tell application "System Events"
  if not (exists process "$APP_NAME") then error "$APP_NAME process is not visible"
  tell process "$APP_NAME"
    repeat with attempt from 1 to 24
      if (count of windows) > 0 then exit repeat
      delay 0.25
    end repeat
    if (count of windows) = 0 then error "no $APP_NAME window is visible"
    set position of window 1 to {80, 80}
    set size of window 1 to {$WIDTH, $HEIGHT}
    delay 1
    set actualSize to size of window 1
    return (item 1 of actualSize as text) & "x" & (item 2 of actualSize as text)
  end tell
end tell
APPLESCRIPT
)"
resize_status=$?
set -e

if [[ "$resize_status" -ne 0 ]]; then
  echo "error: could not resize the $APP_NAME window with System Events" >&2
  echo "$resize_output" >&2

  if window_info="$(windowserver_brev_window_info)"; then
    IFS=$'\t' read -r window_id visible_width visible_height visible_x visible_y visible_name <<<"$window_info"
    echo "    WindowServer fallback saw ${APP_NAME} window ${window_id} (${visible_width}x${visible_height} at ${visible_x},${visible_y})"

    if [[ -n "$SCREENSHOT_PATH" ]]; then
      echo "==> screenshot"
      mkdir -p "$(dirname "$SCREENSHOT_PATH")"
      if screencapture -x -l "$window_id" "$SCREENSHOT_PATH"; then
        echo "    wrote $SCREENSHOT_PATH"
      else
        echo "    warning: could not capture WindowServer screenshot for window ${window_id}"
      fi
    fi

    echo "desktop-compact-layout-check.sh: runtime partial OK"
    echo "next: grant Accessibility permission to Terminal/Codex or manually resize to ${WIDTH}x${HEIGHT} for full compact verification"
    exit 0
  fi

  echo "       grant Accessibility permission to Terminal/Codex, or use the manual checklist in docs/qa/desktop-smoke.md" >&2
  exit 1
fi

actual_width="${resize_output%x*}"
actual_height="${resize_output#*x}"
max_outer_height=$((HEIGHT + MAX_CHROME_DELTA))
if [[ "$actual_width" -ne "$WIDTH" ]]; then
  echo "error: expected outer window width ${WIDTH}, got ${actual_width}" >&2
  exit 1
fi
if [[ "$actual_height" -lt "$HEIGHT" || "$actual_height" -gt "$max_outer_height" ]]; then
  echo "error: expected outer window height ${HEIGHT}..${max_outer_height}, got ${actual_height}" >&2
  echo "       macOS reports Accessibility window size including native titlebar/toolbar chrome" >&2
  exit 1
fi
echo "    OK (${resize_output} outer window for ${WIDTH}x${HEIGHT} content contract)"

if [[ -n "$SCREENSHOT_PATH" ]]; then
  echo "==> screenshot"
  mkdir -p "$(dirname "$SCREENSHOT_PATH")"
  screencapture -x "$SCREENSHOT_PATH"
  echo "    wrote $SCREENSHOT_PATH"
fi

echo "desktop-compact-layout-check.sh: OK"
