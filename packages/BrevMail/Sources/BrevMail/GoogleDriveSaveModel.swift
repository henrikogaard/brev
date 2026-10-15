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
import Foundation

/// Shared in-memory state for a Drive upload and its conflict decision.
@MainActor
final class GoogleDriveSaveModel {
    let accountID: BrevAccount.ID
    let filename: String
    let mimeType: String
    let data: Data
    let originalFileID: String?
    let files: any DriveFileServing
    var isValid: () -> Bool
    var progress: Double?
    var conflict: GoogleDriveClient.File?
    var errorMessage: String?

    private var generation = 0
    private var uploadActive = false

    init(
        accountID: BrevAccount.ID,
        filename: String,
        mimeType: String,
        data: Data,
        originalFileID: String? = nil,
        files: any DriveFileServing,
        isValid: @escaping () -> Bool = { true }
    ) {
        self.accountID = accountID
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
        self.originalFileID = originalFileID
        self.files = files
        self.isValid = isValid
    }

    /// A picker result is a usable destination only when it is a named folder.
    static func isValidFolder(_ pick: GoogleDrivePick) -> Bool {
        pick.isFolder && isValidFolderID(pick.id)
            && pick.mimeType == "application/vnd.google-apps.folder"
    }

    private static func isValidFolderID(_ id: String) -> Bool {
        !id.isEmpty && id.unicodeScalars.allSatisfy {
            ($0.value >= 48 && $0.value <= 57)
                || ($0.value >= 65 && $0.value <= 90)
                || ($0.value >= 97 && $0.value <= 122)
                || $0.value == 95 || $0.value == 45
        }
    }

    /// The source event file is never eligible for replacement.
    static func canReplace(
        conflictID: String,
        originalFileID: String?
    ) -> Bool {
        conflictID != originalFileID
    }

    /// Checks a selected destination and records a conflict, if any.
    func inspectFolder(_ pick: GoogleDrivePick) async throws
        -> GoogleDriveClient.File? {
        guard Self.isValidFolder(pick) else {
            throw GoogleDriveSaveError.invalidFolder
        }
        guard isValid() else { throw GoogleDriveSaveError.sourceUnavailable }
        generation &+= 1
        let currentGeneration = generation
        let found = try await files.existingFile(
            named: filename,
            inFolderID: pick.id,
            accountID: accountID
        )
        guard generation == currentGeneration, isValid() else {
            throw CancellationError()
        }
        conflict = found
        return found
    }

    /// Uploads a new copy or an explicitly selected replacement.
    @discardableResult
    func upload(
        folderID: String,
        replacing fileID: String?,
        onProgress progressHandler: (@Sendable (Int64, Int64) -> Void)? = nil
    ) async throws -> GoogleDriveClient.File {
        guard Self.isValidFolderID(folderID) else {
            throw GoogleDriveSaveError.invalidFolder
        }
        if let fileID, !Self.canReplace(
            conflictID: fileID,
            originalFileID: originalFileID
        ) {
            throw GoogleDriveSaveError.cannotReplaceSource
        }
        guard isValid() else { throw GoogleDriveSaveError.sourceUnavailable }
        generation &+= 1
        let operation = generation
        uploadActive = true
        let onProgress: @Sendable (Int64, Int64) -> Void = { [weak self] sent, total in
            guard total > 0 else { return }
            Task { @MainActor in
                guard let self,
                      self.generation == operation,
                      self.uploadActive
                else { return }
                self.progress = Double(sent) / Double(total)
                progressHandler?(sent, total)
            }
        }
        do {
            let result: GoogleDriveClient.File
            if let fileID {
                result = try await files.update(
                    fileID: fileID,
                    mimeType: mimeType,
                    data: data,
                    accountID: accountID,
                    onProgress: onProgress
                )
            } else {
                result = try await files.create(
                    name: filename,
                    mimeType: mimeType,
                    data: data,
                    parentFolderID: folderID,
                    accountID: accountID,
                    onProgress: onProgress
                )
            }
            guard generation == operation, isValid() else {
                throw CancellationError()
            }
            uploadActive = false
            progress = 1
            return result
        } catch {
            if generation == operation { uploadActive = false }
            guard generation == operation else { throw CancellationError() }
            throw error
        }
    }

    /// Cancels an operation and invalidates callbacks from older operations.
    func cancel() {
        generation &+= 1
        uploadActive = false
        progress = nil
        conflict = nil
    }
}

/// Errors that can be shown without exposing provider response details.
enum GoogleDriveSaveError: Error, LocalizedError, Equatable {
    case invalidFolder
    case cannotReplaceSource
    case sourceUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidFolder:
            String(localized: "Choose a Drive folder before saving.", bundle: .module)
        case .cannotReplaceSource:
            String(localized: "The event attachment can only be saved as a new copy.", bundle: .module)
        case .sourceUnavailable:
            String(localized: "The calendar source changed before saving finished.", bundle: .module)
        }
    }
}
