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

/// What the compose flow does with a picked Drive file (#14).
public enum GoogleDriveAttachResult: Sendable, Equatable {
    /// Download or export the file and add it as a real attachment.
    case attachFile(GoogleDrivePick, export: GoogleDriveExportFormat?)
    /// Insert the file's Drive link into the message body.
    case attachLink(GoogleDrivePick)
}

/// The compose-side Google Drive sheet (#14): opt-in on first use,
/// the Google-hosted picker, then an explicit attach-as-file or
/// attach-as-link choice (with an export-format choice for Google
/// Workspace documents).
struct GoogleDriveAttachSheet: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let account: BrevAccount
    let feature: GoogleDriveFeature
    /// Receives the user's choice; the caller performs the download,
    /// export, or link insert.
    let onAttach: (GoogleDriveAttachResult) -> Void

    private enum Step {
        case optIn
        case picking
        case chosen(GoogleDrivePick)
    }

    @State private var step: Step = .optIn
    @State private var accessToken: String?
    @State private var pickerError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            BrevDivider()
            content
        }
        .frame(minWidth: 560, minHeight: 420)
        .task { await advanceIfEnabled() }
    }

    private var header: some View {
        HStack {
            Text("Google Drive", bundle: .module)
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
                        if let pick = picks.first {
                            step = .chosen(pick)
                        }
                    },
                    onCancel: { dismiss() },
                    onError: { message in pickerError = message }
                )
                .overlay(alignment: .bottom) {
                    if let pickerError {
                        Text(pickerError)
                            .brevFont(.caption)
                            .foregroundStyle(theme.danger.color)
                            .padding(BrevSpacing.sm)
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .chosen(let pick):
            chosenStep(pick)
        }
    }

    /// The explicit per-file choice the issue requires: download as a
    /// real attachment (with an export format for workspace files) or
    /// insert the Drive link.
    @ViewBuilder
    private func chosenStep(_ pick: GoogleDrivePick) -> some View {
        let exports = GoogleDriveExportFormats.options(
            for: pick.mimeType
        )
        VStack(alignment: .leading, spacing: BrevSpacing.md) {
            Label(pick.name, systemImage: "doc")
                .brevFont(.body)
                .foregroundStyle(theme.textPrimary.color)
                .lineLimit(2)
            if pick.isFolder {
                Text(
                    "Folders cannot be attached. Pick a file instead.",
                    bundle: .module
                )
                .brevFont(.caption)
                .foregroundStyle(theme.warning.color)
            }
            if exports.isEmpty, !pick.isFolder {
                Button {
                    onAttach(.attachFile(pick, export: nil))
                    dismiss()
                } label: {
                    Label(
                        "Download and attach",
                        systemImage: "arrow.down.doc"
                    )
                }
            } else if !pick.isFolder {
                ForEach(exports) { format in
                    Button {
                        onAttach(.attachFile(pick, export: format))
                        dismiss()
                    } label: {
                        Label(
                            format.label,
                            systemImage: "arrow.down.doc"
                        )
                    }
                }
            }
            if pick.url != nil {
                Button {
                    onAttach(.attachLink(pick))
                    dismiss()
                } label: {
                    Label(
                        "Insert link",
                        systemImage: "link"
                    )
                }
            }
            Spacer()
            Button {
                step = .picking
            } label: {
                Text("Pick a different file", bundle: .module)
            }
        }
        .padding(BrevSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Advances past the opt-in step once the grant covers
    /// `drive.file` and the picker credentials exist.
    private func advanceIfEnabled() async {
        guard await feature.isEnabled(accountID: account.id),
              let provider = feature.accessToken
        else { return }
        do {
            accessToken = try await provider(account.id)
            step = .picking
        } catch {
            pickerError = error.localizedDescription
        }
    }
}
