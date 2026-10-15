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

/// Presents the explicit, user-triggered event attachment save flow.
struct GoogleDriveEventSaveSheet: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let attachment: PIMEventAttachment
    let accountID: BrevAccount.ID
    let feature: GoogleDriveFeature
    let sourceIsValid: () -> Bool

    private enum Step {
        case intent
        case optIn
        case picking
        case exportChoice([GoogleDriveExportFormat])
        case saving(GoogleDriveEventSaveModel.Prepared)
    }

    @State private var step: Step = .intent
    @State private var accessToken: String?
    @State private var model: GoogleDriveEventSaveModel?
    @State private var errorMessage: String?
    @State private var operationTask: Task<Void, Never>?
    @State private var operationGeneration = 0

    var body: some View {
        GoogleDriveSheetChrome(title: "Save to Google Drive") {
            content
        }
        .onDisappear {
            operationGeneration &+= 1
            operationTask?.cancel()
            operationTask = nil
            model?.cancel()
            model = nil
            accessToken = nil
            step = .intent
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .intent:
            VStack(spacing: BrevSpacing.md) {
                Text(
                    "Save this event attachment to a Drive folder.",
                    bundle: .module
                )
                .brevFont(.body)
                .foregroundStyle(theme.textSecondary.color)
                Button(
                    String(localized: "Continue", bundle: .module)
                ) {
                    startOperation { await begin(operation: $0) }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .optIn:
            GoogleDriveOptInPrompt(
                accountID: accountID,
                feature: feature
            ) {
                startOperation { await loadPicker(operation: $0) }
            }
        case .picking:
            if let accessToken {
                GoogleDrivePickerView(
                    configuration: .init(
                        accessToken: accessToken,
                        developerKey: feature.pickerDeveloperKey,
                        appID: feature.pickerAppID,
                        mode: .files
                    ),
                    onPicked: { picks in
                        startOperation { await picked(picks.first, operation: $0) }
                    },
                    onCancel: { dismiss() },
                    onError: { _ in
                        errorMessage = String(
                            localized: "Google Drive could not prepare this file.",
                            bundle: .module
                        )
                    }
                )
            } else {
                ProgressView()
            }
        case .exportChoice(let formats):
            VStack(spacing: BrevSpacing.sm) {
                Text(
                    "Choose an export format.",
                    bundle: .module
                )
                .brevFont(.body)
                ForEach(formats) { format in
                    Button(format.label) {
                        startOperation {
                            await prepare(format: format, operation: $0)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .saving(let prepared):
            GoogleDriveSaveSheet(
                accountID: accountID,
                feature: feature,
                filename: prepared.filename,
                mimeType: prepared.mimeType,
                data: prepared.data,
                onSaved: { _ in dismiss() },
                originalFileID: prepared.originalFileID,
                isValid: sourceIsValid
            )
        }
        if let errorMessage {
            Text(errorMessage)
                .brevFont(.caption)
                .foregroundStyle(theme.danger.color)
                .padding(BrevSpacing.sm)
        }
    }

    private func begin(operation: Int) async {
        guard let files = feature.files else {
            errorMessage = String(
                localized: "Google Drive is unavailable in this session.",
                bundle: .module
            )
            return
        }
        model = GoogleDriveEventSaveModel(
            attachment: attachment,
            accountID: accountID,
            feature: feature,
            files: files,
            isValid: sourceIsValid
        )
        guard await validateIdentity(requireGrant: false),
              operationGeneration == operation
        else { return }
        if await feature.isEnabled(accountID: accountID) {
            guard await validateIdentity(requireGrant: true),
                  operationGeneration == operation
            else { return }
            await loadPicker(operation: operation)
        } else {
            step = .optIn
        }
    }

    private func loadPicker(operation: Int) async {
        guard await validateIdentity(requireGrant: true),
              operationGeneration == operation
        else { return }
        guard await feature.canPresentPicker(accountID: accountID),
              let provider = feature.accessToken
        else {
            errorMessage = String(
                localized: "The Google picker is not configured in this build.",
                bundle: .module
            )
            return
        }
        do {
            accessToken = try await provider(accountID)
            guard operationGeneration == operation,
                  await validateIdentity(requireGrant: true)
            else { return }
            step = .picking
        } catch {
            errorMessage = String(
                localized: "Google Drive could not authorize this file.",
                bundle: .module
            )
        }
    }

    private func picked(_ pick: GoogleDrivePick?, operation: Int) async {
        guard let pick, let model,
              GoogleDriveEventSaveModel.authorizesPickerID(
                  pick.id,
                  for: attachment.url
              )
        else {
            errorMessage = String(
                localized: "Choose the same file as the event attachment.",
                bundle: .module
            )
            return
        }
        do {
            let metadata = try await model.metadata()
            guard operationGeneration == operation,
                  await validateIdentity(requireGrant: true)
            else { return }
            let formats = GoogleDriveExportFormats.options(for: metadata.mimeType)
            if !formats.isEmpty {
                step = .exportChoice(formats)
            } else {
                await prepare(format: nil, operation: operation)
            }
        } catch is CancellationError {
            return
        } catch {
            guard operationGeneration == operation else { return }
            errorMessage = String(
                localized: "Google Drive could not prepare this file.",
                bundle: .module
            )
        }
    }

    private func prepare(
        format: GoogleDriveExportFormat?,
        operation: Int
    ) async {
        guard let model else { return }
        do {
            let prepared = try await model.prepare(exportFormat: format)
            guard operationGeneration == operation,
                  await validateIdentity(requireGrant: true)
            else { return }
            step = .saving(prepared)
        } catch is CancellationError {
            return
        } catch {
            guard operationGeneration == operation else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? String(
                    localized: "Google Drive could not prepare this file.",
                    bundle: .module
                )
        }
    }

    private func startOperation(
        _ action: @escaping (Int) async -> Void
    ) {
        operationGeneration &+= 1
        let operation = operationGeneration
        operationTask?.cancel()
        operationTask = Task { await action(operation) }
    }

    private func validateIdentity(requireGrant: Bool) async -> Bool {
        guard sourceIsValid(),
              await feature.isEligible(accountID: accountID),
              sourceIsValid()
        else { return false }
        if requireGrant {
            guard await feature.isEnabled(accountID: accountID),
                  sourceIsValid()
            else { return false }
        }
        return true
    }
}
