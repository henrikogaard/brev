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
import BrevCalendar
import BrevDesign
import BrevThemes
import Foundation
import SwiftUI

/// Renders the model-owned, user-initiated event attachment save flow.
struct GoogleDriveEventSaveSheet: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var model: GoogleDriveEventSaveModel

    init(
        attachment: PIMEventAttachment,
        accountID: BrevAccount.ID,
        feature: GoogleDriveFeature,
        files: (any DriveFileServing)? = nil,
        payload: GoogleDriveStagedPayload? = nil,
        sourceIsValid: @escaping () -> Bool
    ) {
        _model = State(
            initialValue: GoogleDriveEventSaveModel(
                attachment: attachment,
                accountID: accountID,
                feature: feature,
                files: files,
                payload: payload,
                isValid: sourceIsValid
            )
        )
    }

    var body: some View {
        GoogleDriveSheetChrome(title: "Save to Google Drive") {
            content
        }
        .onDisappear { model.cancel() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .intent:
            VStack(spacing: BrevSpacing.md) {
                Text(
                    "Save this event attachment to a Drive folder.",
                    bundle: .module
                )
                .brevFont(.body)
                .foregroundStyle(theme.textSecondary.color)
                Button(String(localized: "Continue", bundle: .module)) {
                    model.start()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .optIn:
            GoogleDriveOptInPrompt(
                accountID: model.accountID,
                feature: model.feature,
                operationOwned: true
            ) {
                model.enable()
            }
        case .working:
            ProgressView()
        case .picking(let accessToken):
            let pickerToken = model.pickerOperationToken
            GoogleDrivePickerView(
                configuration: .init(
                    accessToken: accessToken,
                    developerKey: model.feature.pickerDeveloperKey,
                    appID: model.feature.pickerAppID,
                    mode: .files
                ),
                onPicked: { picks in
                    model.picked(picks, pickerToken: pickerToken)
                },
                onCancel: cancelAndDismiss,
                onError: { _ in
                    model.reportPickerFailure(pickerToken: pickerToken)
                }
            )
            .id(pickerToken)
        case .exportChoice(let formats):
            VStack(spacing: BrevSpacing.sm) {
                Text("Choose an export format.", bundle: .module)
                    .brevFont(.body)
                ForEach(formats) { format in
                    Button(format.label) { model.chooseExport(format) }
                        .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .saving:
            GoogleDriveSaveSheet(
                accountID: model.accountID,
                feature: model.feature,
                payload: model.payload,
                onSaved: { _ in
                    model.cancel()
                    dismiss()
                },
                onCancel: {
                    model.cancel()
                    dismiss()
                },
                isValid: model.isValid
            )
        case .finished:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        if let error = model.errorMessage {
            errorText(error)
        }
    }

    private func errorText(_ message: String) -> some View {
        Text(message)
            .brevFont(.caption)
            .foregroundStyle(theme.danger.color)
            .padding(BrevSpacing.sm)
    }

    private func cancelAndDismiss() {
        model.cancel()
        dismiss()
    }
}
