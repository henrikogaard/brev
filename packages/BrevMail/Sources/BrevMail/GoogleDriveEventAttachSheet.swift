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

/// The event-side Google Drive sheet (#14): opt-in on first use,
/// then the Google-hosted picker; the picked file becomes a link
/// attachment on the event draft. Calendar attachments are links by
/// design — providers store a URL, never the bytes.
struct GoogleDriveEventAttachSheet: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    /// The Gmail API account the calendar source is linked to.
    let accountID: BrevAccount.ID
    let feature: GoogleDriveFeature
    /// Receives the link attachment built from the pick.
    let onAttach: (PIMEventAttachment) -> Void

    private enum Step {
        case optIn
        case picking
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
            Text("Attach from Google Drive", bundle: .module)
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
                accountID: accountID,
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
                            attach(pick)
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
        }
    }

    private func advanceIfEnabled() async {
        guard await feature.isEnabled(accountID: accountID),
              await feature.canPresentPicker(accountID: accountID),
              let provider = feature.accessToken
        else {
            if await feature.isEnabled(accountID: accountID) {
                // Granted but the build lacks picker credentials.
                pickerError = String(
                    localized:
                    "The Google picker is not configured in this build.",
                    bundle: .module
                )
            }
            return
        }
        do {
            accessToken = try await provider(accountID)
            step = .picking
        } catch {
            pickerError = error.localizedDescription
        }
    }

    /// The picked file becomes a link attachment: the Drive web link,
    /// its name, and MIME type. The picker returns no webViewLink for
    /// some picks — fall back to the Drive file URL form.
    private func attach(_ pick: GoogleDrivePick) {
        onAttach(Self.attachment(for: pick))
        dismiss()
    }

    /// Maps a picker result to the link attachment the event stores —
    /// Drive web link, name, MIME type. Picks without a webViewLink
    /// fall back to the canonical Drive file URL.
    static func attachment(for pick: GoogleDrivePick) -> PIMEventAttachment {
        PIMEventAttachment(
            url: pick.url
                ?? "https://drive.google.com/file/d/\(pick.id)/view",
            title: pick.name,
            mimeType: pick.mimeType
        )
    }
}
