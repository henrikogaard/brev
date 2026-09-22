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

import BrevBackend
import BrevDesign
import BrevThemes
import Foundation
import SwiftUI

/// The save-to-Drive sheet (#14): opt-in on first use, a Google
/// folder picker for the destination, an explicit conflict choice
/// when Brev already created a same-named file there, then the
/// upload.
struct GoogleDriveSaveSheet: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let account: BrevAccount
    let feature: GoogleDriveFeature
    /// The attachment filename and bytes to upload.
    let filename: String
    let mimeType: String
    let data: Data
    let onSaved: (GoogleDriveClient.File) -> Void

    private enum Step {
        case optIn
        case pickingFolder
        case uploading(folderID: String?)
    }

    @State private var step: Step = .optIn
    @State private var accessToken: String?
    @State private var errorMessage: String?
    /// A same-named Brev-created file in the chosen folder.
    @State private var conflict: GoogleDriveClient.File?
    @State private var pendingFolderID: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            BrevDivider()
            content
        }
        .frame(minWidth: 560, minHeight: 420)
        .task { await advanceIfEnabled() }
        .alert(
            String(localized: "A file with this name exists", bundle: .module),
            isPresented: Binding(
                get: { conflict != nil },
                set: { if !$0 { conflict = nil } }
            )
        ) {
            Button(String(localized: "Replace", bundle: .module)) {
                if let conflict {
                    Task { await upload(replacing: conflict.id) }
                }
            }
            Button(String(localized: "Keep Both", bundle: .module)) {
                Task { await upload(replacing: nil) }
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) {}
        } message: {
            Text(
                "Brev can replace the copy it uploaded earlier, or keep both files.",
                bundle: .module
            )
        }
    }

    private var header: some View {
        HStack {
            Text("Save to Google Drive", bundle: .module)
                .brevFont(.title)
                .foregroundStyle(theme.textPrimary.color)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(theme.textTertiary.color)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(
                String(localized: "Close", bundle: .module)
            )
        }
        .padding(BrevSpacing.md)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .optIn:
            GoogleDriveOptInPrompt(
                account: account,
                feature: feature
            ) {
                Task { await advanceIfEnabled() }
            }
        case .pickingFolder:
            if let accessToken {
                GoogleDrivePickerView(
                    configuration: .init(
                        accessToken: accessToken,
                        developerKey: feature.pickerDeveloperKey,
                        appID: feature.pickerAppID,
                        mode: .folder
                    ),
                    onPicked: { picks in
                        let folder = picks.first
                        Task {
                            await checkConflict(
                                folderID: folder?.id
                            )
                        }
                    },
                    onCancel: { dismiss() },
                    onError: { message in errorMessage = message }
                )
                .overlay(alignment: .bottom) {
                    if let errorMessage {
                        Text(errorMessage)
                            .brevFont(.caption)
                            .foregroundStyle(theme.danger.color)
                            .padding(BrevSpacing.sm)
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .uploading:
            VStack(spacing: BrevSpacing.md) {
                ProgressView()
                Text(
                    "Uploading \(filename)…",
                    bundle: .module
                )
                .brevFont(.body)
                .foregroundStyle(theme.textSecondary.color)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func advanceIfEnabled() async {
        guard await feature.isEnabled(accountID: account.id),
              let provider = feature.accessToken
        else { return }
        do {
            accessToken = try await provider(account.id)
            step = .pickingFolder
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Checks for a same-named Brev-created file in the destination
    /// before uploading so the user picks Replace or Keep Both.
    private func checkConflict(folderID: String?) async {
        guard let files = feature.files else { return }
        pendingFolderID = folderID
        do {
            conflict = try await files.existingFile(
                named: filename,
                inFolderID: folderID,
                accountID: account.id
            )
            if conflict == nil {
                await upload(replacing: nil)
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func upload(replacing fileID: String?) async {
        guard let files = feature.files else {
            errorMessage = String(
                localized: "Google Drive is unavailable in this session.",
                bundle: .module
            )
            return
        }
        step = .uploading(folderID: pendingFolderID)
        do {
            let file: GoogleDriveClient.File
            if let fileID {
                file = try await files.update(
                    fileID: fileID,
                    mimeType: mimeType,
                    data: data,
                    accountID: account.id
                )
            } else {
                file = try await files.create(
                    name: filename,
                    mimeType: mimeType,
                    data: data,
                    parentFolderID: pendingFolderID,
                    accountID: account.id
                )
            }
            onSaved(file)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            step = .pickingFolder
        }
    }
}
