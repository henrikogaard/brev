#!/usr/bin/env bash
# Validate scripts/release-appcast-merge.py: idempotent item replacement
# and the nightly 14-item cap. Uses a fake signature; never calls
# sign_update (ADR-0080 §3).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MERGE="scripts/release-appcast-merge.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

printf 'fake dmg bytes' >"$TMP/Brev-0.1.0.dmg"
printf -- "- Added stable ring\n- Retired beta channel & <tags>\n" >"$TMP/notes.txt"

count_items() { python3 -c "import xml.etree.ElementTree as E,sys;print(len(E.parse('$1').getroot().find('channel').findall('item')))" "$1"; }

merge() {
  python3 "$MERGE" --feed "$1" --version "$2" --build-number "$3" \
    --download-url "https://example.com/$2.dmg" --dmg "$TMP/Brev-0.1.0.dmg" \
    --signature "FAKESIGNATURE==" --notes-file "$TMP/notes.txt" \
    --title "Brev" --max-items "$4" >/dev/null
}

FEED="$TMP/appcast.xml"

# 1. Merge twice with the same version: exactly one item.
merge "$FEED" 0.1.0 2026091700 0
merge "$FEED" 0.1.0 2026091700 0
[[ "$(count_items "$FEED")" == "1" ]] || { echo "ERROR: idempotent merge produced $(count_items "$FEED") items" >&2; exit 1; }

# 2. Required item shape.
for needle in '<sparkle:version>2026091700</sparkle:version>' \
              '<sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>' \
              '<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>' \
              'sparkle:edSignature="FAKESIGNATURE=="' \
              '<![CDATA[<pre>- Added stable ring' \
              'type="application/octet-stream"'; do
  if ! grep -qF "$needle" "$FEED"; then
    echo "ERROR: feed is missing $needle" >&2
    exit 1
  fi
done
if ! grep -q '&amp; &lt;tags&gt;' "$FEED"; then
  echo "ERROR: notes were not HTML-escaped" >&2
  exit 1
fi

# 3. A newer version lands first.
merge "$FEED" 0.2.0 2026091800 0
[[ "$(count_items "$FEED")" == "2" ]] || { echo "ERROR: expected 2 items" >&2; exit 1; }
FIRST_TITLE="$(python3 -c "import xml.etree.ElementTree as E;print(E.parse('$FEED').getroot().find('channel').findall('item')[0].find('title').text)")"
[[ "$FIRST_TITLE" == "0.2.0" ]] || { echo "ERROR: newest item is not first (got $FIRST_TITLE)" >&2; exit 1; }

# 4. Nightly cap: merging beyond 14 keeps exactly 14, newest first.
NFEED="$TMP/appcast-nightly.xml"
for i in $(seq 1 16); do
  merge "$NFEED" "0.1.0-nightly.$i" "2026090$i" 14
done
[[ "$(count_items "$NFEED")" == "14" ]] || { echo "ERROR: nightly cap produced $(count_items "$NFEED") items" >&2; exit 1; }
FIRST="$(python3 -c "import xml.etree.ElementTree as E;print(E.parse('$NFEED').getroot().find('channel').findall('item')[0].find('title').text)")"
[[ "$FIRST" == "0.1.0-nightly.16" ]] || { echo "ERROR: nightly cap did not keep newest first (got $FIRST)" >&2; exit 1; }

# 5. Output remains parseable XML.
python3 -c "import xml.dom.minidom; xml.dom.minidom.parse('$FEED'); xml.dom.minidom.parse('$NFEED')" \
  || { echo "ERROR: merged feeds are not valid XML" >&2; exit 1; }

echo "test-release-appcast.sh: OK"
