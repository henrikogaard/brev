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

    let accountID: BrevAccount.ID
    let feature: GoogleDriveFeature
    /// The attachment filename and bytes to upload.
    let filename: String
    let mimeType: String
    let data: Data
    let onSaved: (GoogleDriveClient.File) -> Void
    let originalFileID: String?
    let isValid: () -> Bool

    init(
        accountID: BrevAccount.ID,
        feature: GoogleDriveFeature,
        filename: String,
        mimeType: String,
        data: Data,
        onSaved: @escaping (GoogleDriveClient.File) -> Void,
        originalFileID: String? = nil,
        isValid: @escaping () -> Bool = { true }
    ) {
        self.accountID = accountID
        self.feature = feature
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
        self.onSaved = onSaved
        self.originalFileID = originalFileID
        self.isValid = isValid
    }

    init(
        account: BrevAccount,
        feature: GoogleDriveFeature,
        filename: String,
        mimeType: String,
        data: Data,
        onSaved: @escaping (GoogleDriveClient.File) -> Void,
        originalFileID: String? = nil,
        isValid: @escaping () -> Bool = { true }
    ) {
        self.init(
            accountID: account.id,
            feature: feature,
            filename: filename,
            mimeType: mimeType,
            data: data,
            onSaved: onSaved,
            originalFileID: originalFileID,
            isValid: isValid
        )
    }

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
    /// Byte-level upload progress, 0...1; nil while indeterminate.
    @State private var uploadProgress: Double?
    /// The in-flight upload task so Cancel aborts it for real.
    @State private var uploadTask: Task<Void, Never>?
    @State private var operationGeneration = 0
    @State private var saveModel: GoogleDriveSaveModel?

    var body: some View {
        GoogleDriveSheetChrome(title: "Save to Google Drive") {
            content
        }
        .task { await advanceIfEnabled() }
        .onDisappear { cancelOperation() }
        .alert(
            String(localized: "A file with this name exists", bundle: .module),
            isPresented: Binding(
                get: { conflict != nil },
                set: { if !$0 { conflict = nil } }
            )
        ) {
            if let conflict,
               GoogleDriveSaveModel.canReplace(
                   conflictID: conflict.id,
                   originalFileID: originalFileID
               ) {
                Button(String(localized: "Replace", bundle: .module)) {
                    startUpload(replacing: conflict.id)
                }
            }
            Button(String(localized: "Keep Both", bundle: .module)) {
                startUpload(replacing: nil)
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) {}
        } message: {
            Text(
                "Brev can replace the copy it uploaded earlier, or keep both files.",
                bundle: .module
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .optIn:
            GoogleDriveOptInPrompt(
                accountID: accountID,
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
                        guard let folder = picks.first,
                              GoogleDriveSaveModel.isValidFolder(folder)
                        else {
                            errorMessage = String(
                                localized: "Choose a valid Drive folder.",
                                bundle: .module
                            )
                            return
                        }
                        startConflictCheck(folder: folder)
                    },
                    onCancel: { dismiss() },
                    onError: { _ in
                        errorMessage = String(
                            localized: "Google Drive could not prepare this file.",
                            bundle: .module
                        )
                    }
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
                if let uploadProgress {
                    ProgressView(value: uploadProgress)
                        .frame(maxWidth: 240)
                } else {
                    ProgressView()
                }
                Text(
                    "Uploading \(filename)…",
                    bundle: .module
                )
                .brevFont(.body)
                .foregroundStyle(theme.textSecondary.color)
                Button(String(localized: "Cancel", bundle: .module)) {
                    cancelOperation()
                    uploadProgress = nil
                    step = .pickingFolder
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func advanceIfEnabled() async {
        guard await feature.isEnabled(accountID: accountID),
              let provider = feature.accessToken
        else { return }
        do {
            accessToken = try await provider(accountID)
            guard await isCurrentAccount() else { return }
            step = .pickingFolder
        } catch {
            errorMessage = String(
                localized: "Google Drive could not authorize this file.",
                bundle: .module
            )
        }
    }

    /// Checks for a same-named Brev-created file in the destination
    /// before uploading so the user picks Replace or Keep Both.
    private func startConflictCheck(folder: GoogleDrivePick) {
        operationGeneration &+= 1
        let operation = operationGeneration
        uploadTask?.cancel()
        uploadTask = Task {
            await checkConflict(folder: folder, operation: operation)
        }
    }

    private func checkConflict(
        folder: GoogleDrivePick,
        operation: Int
    ) async {
        guard let files = feature.files,
              await isCurrentAccount()
        else { return }
        pendingFolderID = folder.id
        let model = GoogleDriveSaveModel(
            accountID: accountID,
            filename: filename,
            mimeType: mimeType,
            data: data,
            originalFileID: originalFileID,
            files: files,
            isValid: isValid
        )
        saveModel = model
        do {
            let result = try await model.inspectFolder(folder)
            guard operationGeneration == operation,
                  await isCurrentAccount()
            else { return }
            conflict = result
            if conflict == nil {
                startUpload(replacing: nil)
            }
        } catch {
            guard operationGeneration == operation else { return }
            errorMessage = (error as? GoogleDriveSaveError)?.errorDescription
                ?? String(
                    localized: "Google Drive could not save this file. Try again.",
                    bundle: .module
                )
        }
    }

    /// Starts the upload on a stored task so the Cancel button can
    /// abort it; byte progress feeds the determinate bar.
    private func startUpload(replacing fileID: String?) {
        guard let folderID = pendingFolderID, !folderID.isEmpty,
              fileID.map({
                  GoogleDriveSaveModel.canReplace(
                      conflictID: $0,
                      originalFileID: originalFileID
                  )
              }) ?? true
        else { return }
        operationGeneration &+= 1
        let operation = operationGeneration
        uploadProgress = nil
        uploadTask = Task { await upload(replacing: fileID, operation: operation) }
    }

    private func upload(replacing fileID: String?, operation: Int) async {
        guard feature.files != nil,
              await isCurrentAccount(),
              operationGeneration == operation,
              let folderID = pendingFolderID, !folderID.isEmpty
        else {
            errorMessage = String(
                localized: "Google Drive could not save this file. Try again.",
                bundle: .module
            )
            return
        }
        step = .uploading(folderID: folderID)
        let onProgress: @Sendable (Int64, Int64) -> Void = { sent, total in
            guard total > 0 else { return }
            Task { @MainActor in
                guard operationGeneration == operation, isValid() else { return }
                uploadProgress = Double(sent) / Double(total)
            }
        }
        do {
            guard let saveModel else { throw GoogleDriveSaveError.sourceUnavailable }
            let file = try await saveModel.upload(
                folderID: folderID,
                replacing: fileID,
                onProgress: onProgress
            )
            guard operationGeneration == operation,
                  await isCurrentAccount()
            else { return }
            onSaved(file)
            dismiss()
        } catch is CancellationError {
            guard operationGeneration == operation else { return }
        } catch {
            guard operationGeneration == operation else { return }
            errorMessage = (error as? GoogleDriveSaveError)?.errorDescription
                ?? String(
                    localized: "Google Drive could not save this file. Try again.",
                    bundle: .module
                )
            step = .pickingFolder
        }
    }

    private func isCurrentAccount() async -> Bool {
        guard isValid(),
              await feature.isEligible(accountID: accountID),
              await feature.isEnabled(accountID: accountID)
        else { return false }
        return isValid()
    }

    private func cancelOperation() {
        operationGeneration &+= 1
        uploadTask?.cancel()
        uploadTask = nil
        saveModel?.cancel()
        saveModel = nil
        uploadProgress = nil
        conflict = nil
    }
}
