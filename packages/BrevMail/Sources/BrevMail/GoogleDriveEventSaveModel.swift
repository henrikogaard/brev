/*
 Brev - Mail Client for macOS and iOS
 Copyright (c) 2026 Brev contributors

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, distribute, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the conditions in the LICENSE file.
 */

import BrevBackend
import BrevCalendar
import Foundation

/// Resolves an event's Drive link and stages bytes for the save flow.
@MainActor
final class GoogleDriveEventSaveModel {
    struct Prepared: Sendable, Equatable {
        let filename: String
        let mimeType: String
        let data: Data
        let originalFileID: String
    }

    let attachment: PIMEventAttachment
    let accountID: BrevAccount.ID
    let feature: GoogleDriveFeature
    let files: any DriveFileServing
    var isValid: () -> Bool

    private var generation = 0

    init(
        attachment: PIMEventAttachment,
        accountID: BrevAccount.ID,
        feature: GoogleDriveFeature,
        files: any DriveFileServing,
        isValid: @escaping () -> Bool = { true }
    ) {
        self.attachment = attachment
        self.accountID = accountID
        self.feature = feature
        self.files = files
        self.isValid = isValid
    }

    /// Returns the only file ID represented by a supported HTTPS Drive link.
    static func fileID(in string: String) -> String? {
        guard let url = URL(string: string),
              url.scheme == "https",
              url.user == nil,
              url.password == nil,
              url.port == nil || url.port == 443,
              url.fragment == nil,
              let host = url.host?.lowercased()
        else { return nil }
        let validID: (String) -> Bool = {
            !$0.isEmpty && $0.unicodeScalars.allSatisfy {
                ($0.value >= 48 && $0.value <= 57)
                    || ($0.value >= 65 && $0.value <= 90)
                    || ($0.value >= 97 && $0.value <= 122)
                    || $0.value == 95 || $0.value == 45
            }
        }
        guard let encodedPath = URLComponents(string: string)?.percentEncodedPath
        else { return nil }
        let pathComponents = encodedPath.components(separatedBy: "/")
        guard pathComponents.first == "",
              !pathComponents.dropFirst().contains("")
        else { return nil }
        let components = Array(pathComponents.dropFirst())
        if host == "drive.google.com" {
            if components.first == "file", components.count >= 3,
               components[1] == "d", components.count <= 4,
               url.query == nil,
               validID(components[2]),
               components.count == 3
               || (components.count == 4
                   && ["view", "edit", "preview"].contains(components[3])) {
                return components[2]
            }
            guard components == ["open"] else { return nil }
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems ?? []
            let ids = items.filter { $0.name == "id" }.compactMap(\.value)
            return items.count == 1 && ids.count == 1 && validID(ids[0])
                ? ids[0] : nil
        }
        guard host == "docs.google.com", components.count >= 3,
              components.count <= 4,
              ["document", "spreadsheets", "presentation"].contains(components[0]),
              components[1] == "d", validID(components[2]),
              url.query == nil
        else { return nil }
        guard components.count == 3
            || ["view", "edit", "preview"].contains(components[3])
        else { return nil }
        return components[2]
    }

    /// Confirms that Picker authorized the exact Drive file in the event URL.
    static func authorizesPickerID(
        _ pickedID: String?,
        for attachmentURL: String
    ) -> Bool {
        guard let pickedID else { return false }
        return pickedID == fileID(in: attachmentURL)
    }

    /// Reads authoritative metadata for the picked file.
    func metadata() async throws -> GoogleDriveClient.File {
        guard let fileID = Self.fileID(in: attachment.url) else {
            throw GoogleDriveEventSaveError.unsupportedLink
        }
        generation &+= 1
        let operation = generation
        try await validate()
        let metadata = try await files.metadata(fileID: fileID, accountID: accountID)
        try await validate()
        guard generation == operation else { throw CancellationError() }
        guard metadata.id == fileID else {
            throw GoogleDriveEventSaveError.mismatchedFile
        }
        try Self.validateDownloadable(metadata)
        return metadata
    }

    /// Explicitly loads metadata and then bytes; no provider call occurs before this.
    func prepare(exportFormat: GoogleDriveExportFormat? = nil) async throws -> Prepared {
        guard let fileID = Self.fileID(in: attachment.url) else {
            throw GoogleDriveEventSaveError.unsupportedLink
        }
        generation &+= 1
        let operation = generation
        try await validate()
        let metadata = try await files.metadata(
            fileID: fileID,
            accountID: accountID
        )
        try await validate()
        guard generation == operation else { throw CancellationError() }
        guard metadata.id == fileID else {
            throw GoogleDriveEventSaveError.mismatchedFile
        }
        try Self.validateDownloadable(metadata)
        if metadata.isWorkspaceDocument {
            guard let exportFormat,
                  GoogleDriveExportFormats.options(for: metadata.mimeType)
                  .contains(exportFormat)
            else { throw GoogleDriveEventSaveError.exportChoiceRequired }
            try await validate()
            let data = try await files.export(
                fileID: fileID,
                mimeType: exportFormat.mimeType,
                accountID: accountID
            )
            try await validate()
            guard generation == operation else { throw CancellationError() }
            return Prepared(
                filename: GoogleDriveExportFormats.exportedFilename(
                    for: metadata.name,
                    format: exportFormat
                ),
                mimeType: exportFormat.mimeType,
                data: data,
                originalFileID: fileID
            )
        }
        try await validate()
        let data = try await files.download(fileID: fileID, accountID: accountID)
        try await validate()
        guard generation == operation else { throw CancellationError() }
        return Prepared(
            filename: metadata.name,
            mimeType: metadata.mimeType,
            data: data,
            originalFileID: fileID
        )
    }

    /// Invalidates all pending work and prevents late completions from staging bytes.
    func cancel() {
        generation &+= 1
    }

    private func validate() async throws {
        guard isValid(),
              await feature.isEligible(accountID: accountID),
              await feature.isEnabled(accountID: accountID),
              isValid()
        else { throw GoogleDriveEventSaveError.sourceUnavailable }
    }

    private static func validateDownloadable(
        _ metadata: GoogleDriveClient.File
    ) throws {
        guard metadata.mimeType != "application/vnd.google-apps.folder",
              !metadata.isShortcut,
              !metadata.mimeType.hasPrefix("application/vnd.google-apps.")
              || metadata.isWorkspaceDocument
        else { throw GoogleDriveEventSaveError.unsupportedFile }
    }
}

enum GoogleDriveEventSaveError: Error, LocalizedError, Equatable {
    case unsupportedLink
    case unsupportedFile
    case exportChoiceRequired
    case mismatchedFile
    case sourceUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedLink:
            String(localized: "This attachment is not a supported Google Drive link.", bundle: .module)
        case .unsupportedFile:
            String(localized: "Folders and shortcuts cannot be saved as attachments.", bundle: .module)
        case .exportChoiceRequired:
            String(localized: "Choose an export format before saving this Google document.", bundle: .module)
        case .mismatchedFile:
            String(localized: "Google Drive returned a different file than the selected attachment.", bundle: .module)
        case .sourceUnavailable:
            String(localized: "The calendar source changed before saving finished.", bundle: .module)
        }
    }
}
