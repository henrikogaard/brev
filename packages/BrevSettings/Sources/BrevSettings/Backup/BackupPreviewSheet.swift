/*
 Brev - Mail Client for macOS and iOS
 Copyright (c) 2026 Brev contributors

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the conditions in the LICENSE file.
 */

import BrevDesign
import BrevThemes
import SwiftUI

extension BackupPreview: Identifiable {
    var id: URL { url }
}

/// Restore confirmation sheet: what the backup contains, a Merge/Replace
/// choice, and the credentials-never-included notice (ADR-0076 decision 4).
struct BackupPreviewSheet: View {
    @Environment(\.brevTheme) private var theme

    let preview: BackupPreview
    let onCancel: () -> Void
    let onRestore: (BackupRestoreMode, _ includeMail: Bool) -> Void

    @State private var mode: BackupRestoreMode = .merge
    @State private var includeMail = true

    var body: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.lg) {
            Text("Restore Brev backup", bundle: .module)
                .brevFont(.headline)
            Text(preview.url.lastPathComponent)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)

            countsTable

            if preview.skippedUnknownKeys > 0 {
                Text(
                    "^[\(preview.skippedUnknownKeys) setting](inflect: true) from a newer Brev version will be left untouched.",
                    bundle: .module
                )
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
            }
            if preview.alreadySignedInAccounts > 0 {
                Text(
                    "\(preview.alreadySignedInAccounts) accounts are already signed in and will be skipped.",
                    bundle: .module
                )
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
            }

            Picker(String(localized: "Restore mode", bundle: .module), selection: $mode) {
                Text("Merge", bundle: .module).tag(BackupRestoreMode.merge)
                Text("Replace", bundle: .module).tag(BackupRestoreMode.replace)
            }
            .pickerStyle(.segmented)

            Text(modeExplanation)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)

            if preview.mailFolderCount > 0 {
                Toggle(
                    String(
                        localized: "Include local folders (\(ByteCountFormatter.string(fromByteCount: preview.mailBytes, countStyle: .file)))",
                        bundle: .module
                    ),
                    isOn: $includeMail
                )
            }

            SettingsInfoCallout(
                symbolName: "lock.shield",
                message: String(
                    localized: "Backups never include passwords or tokens. Restored accounts ask you to sign in.",
                    bundle: .module
                ),
                tone: .info
            )

            HStack {
                Spacer()
                Button(String(localized: "Cancel", bundle: .module), role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Restore", bundle: .module)) { onRestore(mode, includeMail) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(BrevSpacing.xl)
        .frame(minWidth: minimumSheetWidth)
    }

    /// iPhone sheets are already narrower than 420pt — a minimum width would
    /// clip; only macOS needs it.
    private var minimumSheetWidth: CGFloat? {
        #if os(macOS)
        420
        #else
        nil
        #endif
    }

    private var modeExplanation: String {
        switch mode {
        case .merge:
            String(
                localized: "Keeps your current rules, signatures, and lists, and adds anything missing from the backup.",
                bundle: .module
            )
        case .replace:
            String(
                localized: "Overwrites the settings included in this backup with the backup's values.",
                bundle: .module
            )
        }
    }

    private var countsTable: some View {
        Grid(alignment: .leading, horizontalSpacing: BrevSpacing.lg, verticalSpacing: BrevSpacing.xs) {
            GridRow {
                Text("Contents", bundle: .module)
                    .brevFont(.headline)
                Text("Created with Brev \(preview.sourceAppVersion)", bundle: .module)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
            }
            countRow(String(localized: "Accounts", bundle: .module), preview.accountCount)
            countRow(String(localized: "Rules", bundle: .module), preview.rulesCount)
            countRow(String(localized: "Smart Views", bundle: .module), preview.smartViewCount)
            countRow(String(localized: "Signatures", bundle: .module), preview.signatureCount)
            countRow(String(localized: "Templates", bundle: .module), preview.templateCount)
            countRow(String(localized: "VIP senders", bundle: .module), preview.vipSenderCount)
            countRow(
                String(localized: "Other preference groups", bundle: .module),
                preview.otherFamiliesCount
            )
            if preview.mailFolderCount > 0 {
                countRow(
                    String(localized: "Local folders", bundle: .module),
                    preview.mailFolderCount
                )
            }
        }
    }

    private func countRow(_ label: String, _ count: Int) -> some View {
        GridRow {
            Text(label)
                .brevFont(.body)
            Text("\(count)")
                .brevFont(.body)
                .foregroundStyle(theme.textSecondary.color)
        }
    }
}
