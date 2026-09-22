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

/// The opt-in prompt shown before the first Drive action (#14).
///
/// Drive stays dark until the user confirms; confirming runs the
/// account's OAuth re-authorization with `drive.file` unioned
/// into the grant. Declining leaves the feature untouched.
struct GoogleDriveOptInPrompt: View {
    @Environment(\.brevTheme) private var theme
    let account: BrevAccount
    let feature: GoogleDriveFeature
    /// Runs after a successful grant — the sheet advances to the
    /// picker.
    let onEnabled: () -> Void

    init(
        account: BrevAccount,
        feature: GoogleDriveFeature,
        onEnabled: @escaping () -> Void
    ) {
        self.account = account
        self.feature = feature
        self.onEnabled = onEnabled
    }

    /// Identity-only variant for flows that know the account ID but
    /// not the account record (calendar event attachments, #14).
    init(
        accountID: BrevAccount.ID,
        feature: GoogleDriveFeature,
        onEnabled: @escaping () -> Void
    ) {
        // The prompt only reads the account's ID; a minimal record
        // keeps the shared layout without fetching the account.
        self.init(
            account: BrevAccount(
                id: accountID,
                displayName: "",
                emailAddress: "",
                backendIdentifier: BrevAccount.gmailAPIBackendIdentifier
            ),
            feature: feature,
            onEnabled: onEnabled
        )
    }

    var body: some View {
        VStack(spacing: BrevSpacing.lg) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.system(size: 32))
                .foregroundStyle(theme.accent.color)
            Text("Google Drive attachments", bundle: .module)
                .brevFont(.title)
                .foregroundStyle(theme.textPrimary.color)
            Text(
                "Brev asks Google for per-file Drive access the first time you attach or save. You choose each file in Google's picker; Brev never browses your Drive.",
                bundle: .module
            )
            .brevFont(.body)
            .foregroundStyle(theme.textSecondary.color)
            .multilineTextAlignment(.center)
            if feature.isEnabling {
                ProgressView()
            }
            if let lastError = feature.lastError {
                Text(lastError)
                    .brevFont(.caption)
                    .foregroundStyle(theme.danger.color)
                    .multilineTextAlignment(.center)
            }
            Button {
                Task {
                    try? await feature.enable(accountID: account.id)
                    if await feature.isEnabled(accountID: account.id) {
                        onEnabled()
                    }
                }
            } label: {
                Text("Enable Google Drive", bundle: .module)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(feature.isEnabling)
        }
        .padding(BrevSpacing.xl)
    }
}

/// One export option for a Google Workspace document.
public struct GoogleDriveExportFormat: Sendable, Hashable, Identifiable {
    public let label: String
    public let mimeType: String
    /// Filename extension appended when the picked name lacks one.
    public let fileExtension: String

    public var id: String { mimeType }

    public init(label: String, mimeType: String, fileExtension: String) {
        self.label = label
        self.mimeType = mimeType
        self.fileExtension = fileExtension
    }
}

/// Export options per Google Workspace MIME type (#14). Files that
/// are not workspace documents download directly; types without a
/// listed export fall back to link-only attaching.
public enum GoogleDriveExportFormats {
    public static func options(for mimeType: String) -> [GoogleDriveExportFormat] {
        switch mimeType {
        case "application/vnd.google-apps.document":
            [
                GoogleDriveExportFormat(
                    label: "PDF", mimeType: "application/pdf",
                    fileExtension: ".pdf"
                ),
                GoogleDriveExportFormat(
                    label: "Word (.docx)",
                    mimeType:
                    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                    fileExtension: ".docx"
                ),
            ]
        case "application/vnd.google-apps.spreadsheet":
            [
                GoogleDriveExportFormat(
                    label: "PDF", mimeType: "application/pdf",
                    fileExtension: ".pdf"
                ),
                GoogleDriveExportFormat(
                    label: "Excel (.xlsx)",
                    mimeType:
                    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                    fileExtension: ".xlsx"
                ),
                GoogleDriveExportFormat(
                    label: "CSV", mimeType: "text/csv",
                    fileExtension: ".csv"
                ),
            ]
        case "application/vnd.google-apps.presentation":
            [
                GoogleDriveExportFormat(
                    label: "PDF", mimeType: "application/pdf",
                    fileExtension: ".pdf"
                ),
                GoogleDriveExportFormat(
                    label: "PowerPoint (.pptx)",
                    mimeType:
                    "application/vnd.openxmlformats-officedocument.presentationml.presentation",
                    fileExtension: ".pptx"
                ),
            ]
        default:
            []
        }
    }

    /// The filename for an exported attachment — the Drive name plus
    /// the format's extension when it is missing.
    public static func exportedFilename(
        for name: String,
        format: GoogleDriveExportFormat
    ) -> String {
        name.lowercased().hasSuffix(format.fileExtension)
            ? name
            : name + format.fileExtension
    }
}
