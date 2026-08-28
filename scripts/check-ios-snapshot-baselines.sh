#!/usr/bin/env bash
# Verify the iOS snapshot lane's required references and explicit debt list.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
snapshot_root="$repo_root/packages/BrevMail/Tests/BrevMailTests/__Snapshots__"
metadata="$repo_root/docs/qa/ios-snapshot-baselines.md"
workflow="$repo_root/.github/workflows/build.yml"

required=(
  "$snapshot_root/BrevMailRootViewSnapshotTests/rootViewWideLayout.root-wide.png"
  "$snapshot_root/MessageDetailViewSnapshotTests/bodyLoadErrorState.body-load-error.png"
  "$snapshot_root/FolderSidebarSnapshotTests/allInboxesGlobalAlignment.all-inboxes-global-alignment.png"
  "$snapshot_root/MailRootStatusRailSnapshotTests/downloadingRailStacksAboveWorkspace.downloading-rail.png"
  "$snapshot_root/MessageListRowSnapshotTests/readMessageSender.bold-read-sender.png"
  "$snapshot_root/ThreadInlineChildRowSnapshotTests/selectedChildRow.selected-child.png"
  "$snapshot_root/MailContextColumnSnapshotTests/senderPanelLoadedState.sender-panel-loaded.png"
)

for reference in "${required[@]}"; do
  if [[ ! -s "$reference" ]]; then
    echo "ios-snapshot-baselines: required reference is missing or empty: ${reference#"$repo_root/"}" >&2
    exit 1
  fi
done

if [[ ! -s "$metadata" ]]; then
  echo "ios-snapshot-baselines: missing metadata: ${metadata#"$repo_root/"}" >&2
  exit 1
fi

# A removed/renamed suite must be accounted for in the metadata before it can
# disappear from the required lane. This catches stale workflow selectors such
# as the retired BrevMailV2SnapshotTests target.
if grep -Fq 'BrevMailV2SnapshotTests' "$workflow"; then
  echo "ios-snapshot-baselines: workflow still selects retired BrevMailV2SnapshotTests" >&2
  exit 1
fi

for suite in \
  BrevMailSnapshotTests \
  BrevMailViewSnapshotTests \
  BrevMailRootViewSnapshotTests \
  MessageNoteSheetSnapshotTests \
  AllAttachmentsViewSnapshotTests \
  ImportProgressBannerSnapshotTests \
  SavedSearchEditorViewSnapshotTests \
  MessageRawSourceSheetSnapshotTests; do
  if ! grep -Fq "$suite" "$metadata"; then
    echo "ios-snapshot-baselines: deferred suite is not documented: $suite" >&2
    exit 1
  fi
done

echo "ios-snapshot-baselines: required references and deferred-suite metadata are present"
