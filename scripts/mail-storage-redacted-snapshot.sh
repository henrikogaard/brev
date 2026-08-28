#!/usr/bin/env bash
# Print redacted Brev-owned local mail storage totals for live QA evidence.

set -euo pipefail

usage() {
  cat <<'EOF'
usage: scripts/mail-storage-redacted-snapshot.sh --account-id <id> [--app-support-root <path>]
       scripts/mail-storage-redacted-snapshot.sh --self-test

Prints aggregate local storage bytes/file counts for one account without
printing the account id, email address, home directory, or full cache paths.

The account id is used only to derive Brev's on-disk hex key. Output includes
only redacted category labels and aggregate counts suitable for #257/#263 live
Settings evidence.

Options:
  --account-id <id>          Brev account id to inspect.
  --app-support-root <path>  Override Application Support root for tests.
                             Defaults to "$HOME/Library/Application Support".
  --self-test                Build a temporary storage tree and verify output
                             categories, counts, and redaction behavior.
EOF
}

account_id=""
app_support_root="${BREV_APP_SUPPORT_ROOT:-$HOME/Library/Application Support}"
self_test=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --self-test)
      self_test=1
      shift
      ;;
    --account-id)
      if [[ $# -lt 2 ]]; then
        echo "mail-storage-redacted-snapshot.sh: --account-id requires a value" >&2
        exit 2
      fi
      account_id="$2"
      shift 2
      ;;
    --app-support-root)
      if [[ $# -lt 2 ]]; then
        echo "mail-storage-redacted-snapshot.sh: --app-support-root requires a value" >&2
        exit 2
      fi
      app_support_root="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "mail-storage-redacted-snapshot.sh: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ $self_test -eq 1 ]]; then
  tmp_root="$(mktemp -d)"
  trap 'rm -rf "$tmp_root"' EXIT

  test_account="storage-self-test@example.invalid"
  test_key="$(LC_ALL=C printf '%s' "$test_account" | od -An -tx1 -v | tr -d ' \n')"
  mkdir -p "$tmp_root/Brev/Cache/$test_key/headers" \
    "$tmp_root/Brev/Drafts/$test_key" \
    "$tmp_root/Brev/sync-cache"
  printf 'cached-header' >"$tmp_root/Brev/Cache/$test_key/headers/1.json"
  printf 'cached-body' >"$tmp_root/Brev/Cache/$test_key/body.eml"
  printf 'draft' >"$tmp_root/Brev/Drafts/$test_key/draft.json"
  printf 'sqlite' >"$tmp_root/Brev/sync-cache/$test_key.sqlite"
  printf 'wal' >"$tmp_root/Brev/sync-cache/$test_key.sqlite-wal"

  output="$(bash "$0" --account-id "$test_account" --app-support-root "$tmp_root")"
  grep -q '| Mail cache | yes |' <<<"$output"
  grep -q '| Draft staging | yes |' <<<"$output"
  grep -q '| Search index database | yes |' <<<"$output"
  grep -q '| Total | n/a |' <<<"$output"
  grep -q '| Mail cache | yes | .* | 2 |' <<<"$output"
  grep -q '| Draft staging | yes | .* | 1 |' <<<"$output"
  grep -q '| Search index database | yes | .* | 2 |' <<<"$output"
  if grep -q "$test_account\|$test_key\|$tmp_root" <<<"$output"; then
    echo "mail-storage-redacted-snapshot.sh: self-test failed; output leaked private identifiers" >&2
    exit 1
  fi

  echo "mail-storage-redacted-snapshot.sh: self-test OK"
  exit 0
fi

if [[ -z "$account_id" ]]; then
  echo "mail-storage-redacted-snapshot.sh: --account-id is required" >&2
  usage >&2
  exit 2
fi

hex_key() {
  LC_ALL=C printf '%s' "$1" | od -An -tx1 -v | tr -d ' \n'
}

directory_metrics() {
  local path="$1"
  local bytes=0
  local files=0
  local file size

  if [[ -d "$path" ]]; then
    while IFS= read -r -d '' file; do
      size="$(allocated_file_bytes "$file")"
      bytes=$((bytes + size))
      files=$((files + 1))
    done < <(find "$path" -type f -print0)
  fi

  printf '%s %s\n' "$bytes" "$files"
}

index_metrics() {
  local directory="$1"
  local key="$2"
  local bytes=0
  local files=0
  local path size

  for suffix in "" "-wal" "-shm"; do
    path="$directory/${key}.sqlite${suffix}"
    if [[ -f "$path" ]]; then
      size="$(allocated_file_bytes "$path")"
      bytes=$((bytes + size))
      files=$((files + 1))
    fi
  done

  printf '%s %s\n' "$bytes" "$files"
}

allocated_file_bytes() {
  local path="$1"
  local blocks
  local logical_size

  blocks="$(stat -f '%b' "$path")"
  logical_size="$(stat -f '%z' "$path")"
  if [[ "$blocks" =~ ^[0-9]+$ && "$blocks" -gt 0 ]]; then
    printf '%s\n' "$((blocks * 512))"
    return
  fi
  printf '%s\n' "$logical_size"
}

print_row() {
  local label="$1"
  local exists="$2"
  local bytes="$3"
  local files="$4"
  printf '| %s | %s | %s | %s |\n' "$label" "$exists" "$bytes" "$files"
}

account_key="$(hex_key "$account_id")"

cache_dir="$app_support_root/Brev/Cache/$account_key"
drafts_dir="$app_support_root/Brev/Drafts/$account_key"
index_dir="$app_support_root/Brev/sync-cache"

read -r cache_bytes cache_files < <(directory_metrics "$cache_dir")
read -r draft_bytes draft_files < <(directory_metrics "$drafts_dir")
read -r index_bytes index_files < <(index_metrics "$index_dir" "$account_key")

total_bytes=$((cache_bytes + draft_bytes + index_bytes))
total_files=$((cache_files + draft_files + index_files))

echo "# Brev Mail Storage Snapshot"
echo ""
echo "- Account key: redacted"
echo "- Paths: redacted"
echo "- Byte basis: allocated file bytes from Brev-owned storage files"
echo ""
echo "| Category | Exists | Bytes | File objects |"
echo "|----------|--------|-------|--------------|"
print_row "Mail cache" "$([[ -d "$cache_dir" ]] && echo yes || echo no)" "$cache_bytes" "$cache_files"
print_row "Draft staging" "$([[ -d "$drafts_dir" ]] && echo yes || echo no)" "$draft_bytes" "$draft_files"
print_row "Search index database" "$([[ $index_files -gt 0 ]] && echo yes || echo no)" "$index_bytes" "$index_files"
print_row "Total" "n/a" "$total_bytes" "$total_files"
