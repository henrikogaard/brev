#!/usr/bin/env bash
# Print a usable iOS Simulator destination for the selected Xcode.
#
# The available simulator name and runtime move with Xcode releases. Keep
# callers independent of a retired OS/device pair while allowing CI or a
# developer to pin an exact destination with BREV_IOS_RUNTIME and
# BREV_IOS_DEVICE.

set -euo pipefail

runtime="${BREV_IOS_RUNTIME:-}"
device="${BREV_IOS_DEVICE:-}"

if [[ -z "$runtime" ]]; then
  runtime="$(
    xcrun simctl list runtimes available |
      awk '/^[[:space:]]*iOS [0-9]+(\.[0-9]+)* \(/ { print $2 }' |
      sort -V |
      tail -n 1
  )"
fi

if [[ -z "$runtime" ]]; then
  echo "ios-simulator-destination: no available iOS runtime found" >&2
  exit 1
fi

if ! xcrun simctl list runtimes available | grep -Eq "^[[:space:]]*iOS ${runtime//./\\.} \("; then
  echo "ios-simulator-destination: iOS ${runtime} is not installed" >&2
  exit 1
fi

if [[ -z "$device" ]]; then
  device="$(
    xcrun simctl list devices available |
      awk -v header="-- iOS ${runtime} --" '
        $0 == header { in_runtime = 1; next }
        in_runtime && /^-- / { exit }
        in_runtime && /^[[:space:]]+iPhone / {
          line = $0
          sub(/^[[:space:]]+/, "", line)
          sub(/[[:space:]]+\([^)]*\).*/, "", line)
          print line
          exit
        }
      '
  )"
fi

if [[ -z "$device" ]]; then
  echo "ios-simulator-destination: no available iPhone found for iOS ${runtime}" >&2
  echo "Set BREV_IOS_RUNTIME and BREV_IOS_DEVICE to an installed pair." >&2
  exit 1
fi

if ! xcrun simctl list devices available | awk -v header="-- iOS ${runtime} --" -v device="$device" '
  $0 == header { in_runtime = 1; next }
  in_runtime && /^-- / { exit }
  in_runtime && $0 ~ "^[[:space:]]+" device " \\(" { found = 1 }
  END { exit(found ? 0 : 1) }
'; then
  echo "ios-simulator-destination: ${device} is not available on iOS ${runtime}" >&2
  exit 1
fi

printf 'platform=iOS Simulator,OS=%s,name=%s\n' "$runtime" "$device"
