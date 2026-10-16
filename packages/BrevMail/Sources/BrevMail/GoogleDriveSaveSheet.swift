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

/// Presents the shared Google Drive save flow for event and mail attachments.
struct GoogleDriveSaveSheet: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    private let feature: GoogleDriveFeature
    @State private var model: GoogleDriveSaveModel

    init(
        accountID: BrevAccount.ID,
        feature: GoogleDriveFeature,
        payload: GoogleDriveStagedPayload,
        onSaved: @escaping (GoogleDriveClient.File) -> Void,
        onCancel: (() -> Void)? = nil,
        isValid: @escaping () -> Bool = { true }
    ) {
        self.feature = feature
        _model = State(
            initialValue: GoogleDriveSaveModel(
                accountID: accountID,
                payload: payload,
                files: feature.files,
                isValid: isValid,
                feature: feature,
                onSaved: onSaved,
                onCancel: onCancel
            )
        )
    }

    /// Compatibility initializer for callers that stage bytes directly.
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
        self.init(
            accountID: accountID,
            feature: feature,
            payload: GoogleDriveStagedPayload(
                filename: filename,
                mimeType: mimeType,
                bytes: data,
                sourceFileID: originalFileID
            ),
            onSaved: onSaved,
            isValid: isValid
        )
    }

    /// Compatibility initializer for existing mail sheet call sites.
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

    var body: some View {
        GoogleDriveSheetChrome(title: "Save to Google Drive") {
            content
        }
        .task { model.start() }
        .onDisappear {
            model.cancel()
        }
        .onChange(of: model.phase) { _, phase in
            if phase == .finished {
                dismiss()
            }
        }
        .alert(
            String(localized: "A file with this name exists", bundle: .module),
            isPresented: Binding(
                get: { model.conflict != nil },
                set: { _ in }
            )
        ) {
            if let conflict = model.conflict,
               GoogleDriveSaveModel.canReplace(
                   conflictID: conflict.id,
                   originalFileID: model.originalFileID
               ) {
                Button(String(localized: "Replace", bundle: .module)) {
                    model.replaceConflict()
                }
            }
            Button(String(localized: "Keep Both", bundle: .module)) {
                model.keepBoth()
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) {
                model.cancelConflict()
            }
        } message: {
            Text(
                "Brev can replace the copy it uploaded earlier, or keep both files.",
                bundle: .module
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .optIn:
            GoogleDriveOptInPrompt(
                accountID: model.accountID,
                feature: feature,
                operationOwned: true
            ) {
                model.enable()
            }
        case .working:
            ProgressView()
        case .retry:
            Button(String(localized: "Retry", bundle: .module)) {
                model.start()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .picking(let accessToken):
            let pickerToken = model.pickerOperationToken
            GoogleDrivePickerView(
                configuration: .init(
                    accessToken: accessToken,
                    developerKey: feature.pickerDeveloperKey,
                    appID: feature.pickerAppID,
                    mode: .folder
                ),
                onPicked: { picks in
                    model.pickedFolder(
                        picks.first,
                        pickerToken: pickerToken
                    )
                },
                onCancel: cancelAndDismiss,
                onError: { _ in
                    model.reportPickerFailure(pickerToken: pickerToken)
                }
            )
            .id(pickerToken)
        case .uploading:
            VStack(spacing: BrevSpacing.md) {
                if let progress = model.progress {
                    ProgressView(value: progress)
                        .frame(maxWidth: 240)
                } else {
                    ProgressView()
                }
                Text(
                    "Uploading \(model.payload.filename ?? "")…",
                    bundle: .module
                )
                .brevFont(.body)
                .foregroundStyle(theme.textSecondary.color)
                Button(String(localized: "Cancel", bundle: .module)) {
                    cancelAndDismiss()
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .conflict:
            ProgressView()
        case .finished:
            ProgressView()
        }
        if let error = model.errorMessage {
            Text(error)
                .brevFont(.caption)
                .foregroundStyle(theme.danger.color)
                .padding(BrevSpacing.sm)
        }
    }

    private func cancelAndDismiss() {
        model.cancel()
        dismiss()
    }
}
