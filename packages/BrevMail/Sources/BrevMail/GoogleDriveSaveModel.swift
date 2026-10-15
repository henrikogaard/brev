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
import Observation

/// Shared state for a Drive upload and its conflict decision (#14).
///
/// The bytes live in the shared payload, so cancelling, dismissing, or
/// completing the flow drops them for the parent flow too. Cancelling
/// is terminal: a retry is a fresh user action with fresh preparation,
/// while ordinary provider errors stay retryable.
@Observable
@MainActor
final class GoogleDriveSaveModel {
    enum Phase: Equatable {
        case optIn
        case picking(accessToken: String)
        case working
        case retry
        case uploading
        case conflict(GoogleDriveClient.File)
        case finished
    }

    let accountID: BrevAccount.ID
    let feature: GoogleDriveFeature
    /// The bytes to upload, shared by reference with the parent flow.
    let payload: GoogleDriveStagedPayload
    let files: (any DriveFileServing)?
    var isValid: () -> Bool
    var onSaved: ((GoogleDriveClient.File) -> Void)?
    var onCancel: (() -> Void)?
    var progress: Double?
    var conflict: GoogleDriveClient.File?
    var errorMessage: String?
    private(set) var phase: Phase = .picking(accessToken: "")

    private let lifetime = GoogleDriveOperationLifetime()
    private var uploadActive = false
    private var pendingFolderID: String?
    private var pickerAccessToken: String?
    private(set) var pickerOperationToken: Int?

    init(
        accountID: BrevAccount.ID,
        payload: GoogleDriveStagedPayload,
        files: (any DriveFileServing)? = nil,
        isValid: @escaping () -> Bool = { true },
        feature: GoogleDriveFeature,
        onSaved: ((GoogleDriveClient.File) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.accountID = accountID
        self.feature = feature
        self.payload = payload
        self.files = files ?? feature.files
        self.isValid = isValid
        self.onSaved = onSaved
        self.onCancel = onCancel
        phase = .optIn
    }

    /// The Drive file the bytes came from; it is never overwritten.
    var originalFileID: String? { payload.sourceFileID }

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

    /// Starts the opt-in or folder-picker phase for this operation.
    func start() {
        errorMessage = nil
        lifetime.start { [weak self] token in
            await self?.advance(token: token)
        }
    }

    /// Enables Drive for this operation, then opens the folder picker.
    func enable() {
        lifetime.start { [weak self] token in
            await self?.enableAndAdvance(token: token)
        }
    }

    /// Accepts the Picker folder result and starts conflict lookup.
    func pickedFolder(
        _ pick: GoogleDrivePick?,
        pickerToken: Int? = nil
    ) {
        guard let pickerToken = pickerToken ?? pickerOperationToken,
              lifetime.isCurrent(pickerToken),
              isValid()
        else { return }
        pickerOperationToken = nil
        phase = .working
        lifetime.start { [weak self] token in
            await self?.inspect(pick, token: token)
        }
    }

    /// Explicitly replaces the named Brev copy, if one was found.
    func replaceConflict() {
        guard let existingConflict = conflict,
              Self.canReplace(
                  conflictID: existingConflict.id,
                  originalFileID: originalFileID
              ),
              let pendingFolderID
        else { return }
        let conflictID = existingConflict.id
        conflict = nil
        beginUpload(folderID: pendingFolderID, replacing: conflictID)
    }

    /// Keeps both copies, creating a new file in the selected folder.
    func keepBoth() {
        guard conflict != nil, let pendingFolderID else { return }
        conflict = nil
        beginUpload(folderID: pendingFolderID, replacing: nil)
    }

    /// Returns a dismissed conflict choice to the folder picker.
    func cancelConflict() {
        guard conflict != nil, let pickerAccessToken else { return }
        conflict = nil
        self.pickerAccessToken = pickerAccessToken
        lifetime.start { [weak self] token in
            guard let self,
                  await validate(token: token, requireGrant: true),
                  lifetime.isCurrent(token),
                  isValid()
            else { return }
            pickerOperationToken = token
            phase = .picking(accessToken: pickerAccessToken)
        }
    }

    /// Clears provider-specific Picker error details.
    func reportPickerFailure(pickerToken: Int? = nil) {
        guard let token = pickerToken ?? pickerOperationToken,
              token == pickerOperationToken,
              lifetime.isCurrent(token),
              isValid()
        else { return }
        lifetime.cancel()
        pickerAccessToken = nil
        pickerOperationToken = nil
        pendingFolderID = nil
        conflict = nil
        progress = nil
        phase = .retry
        errorMessage = Self.genericSaveFailure
    }

    /// Checks a selected destination and records a conflict, if any.
    func inspectFolder(_ pick: GoogleDrivePick) async throws
        -> GoogleDriveClient.File? {
        guard Self.isValidFolder(pick) else {
            throw GoogleDriveSaveError.invalidFolder
        }
        guard let filename = payload.filename, payload.isStaged else {
            throw GoogleDriveSaveError.payloadUnavailable
        }
        guard let files else { throw GoogleDriveSaveError.serviceUnavailable }
        guard let token = lifetime.nextToken() else {
            throw GoogleDriveSaveError.sourceUnavailable
        }
        guard await validate(token: token, requireGrant: true) else {
            throw GoogleDriveSaveError.sourceUnavailable
        }
        guard lifetime.isCurrent(token), isValid() else {
            throw CancellationError()
        }
        let found = try await files.existingFile(
            named: filename,
            inFolderID: pick.id,
            accountID: accountID
        )
        guard lifetime.isCurrent(token),
              await validate(token: token, requireGrant: true)
        else {
            throw CancellationError()
        }
        guard lifetime.isCurrent(token), isValid() else {
            throw CancellationError()
        }
        conflict = found
        pendingFolderID = pick.id
        return found
    }

    /// Uploads a new copy or an explicitly selected replacement.
    @discardableResult
    func upload(
        folderID: String,
        replacing fileID: String?,
        onProgress progressHandler: (@Sendable (Int64, Int64) -> Void)? = nil
    ) async throws -> GoogleDriveClient.File {
        guard !lifetime.isTerminal else {
            throw GoogleDriveSaveError.sourceUnavailable
        }
        guard Self.isValidFolderID(folderID) else {
            throw GoogleDriveSaveError.invalidFolder
        }
        if let fileID, !Self.canReplace(
            conflictID: fileID,
            originalFileID: originalFileID
        ) {
            throw GoogleDriveSaveError.cannotReplaceSource
        }
        guard let operation = lifetime.nextToken() else {
            throw GoogleDriveSaveError.sourceUnavailable
        }
        do {
            let result = try await executeUpload(
                folderID: folderID,
                replacing: fileID,
                token: operation,
                progressHandler: progressHandler
            )
            finalizeUpload(result, token: operation)
            return result
        } catch {
            if lifetime.isCurrent(operation) { uploadActive = false }
            guard lifetime.isCurrent(operation) else { throw CancellationError() }
            throw error
        }
    }

    /// Ends the save for good and drops the staged bytes and state.
    func cancel() {
        let shouldNotify = !lifetime.isTerminal
        lifetime.finish()
        uploadActive = false
        progress = nil
        conflict = nil
        pendingFolderID = nil
        pickerAccessToken = nil
        pickerOperationToken = nil
        errorMessage = nil
        payload.clear()
        phase = .finished
        if shouldNotify { onCancel?() }
    }

    private func advance(token: Int) async {
        guard await validate(token: token, requireGrant: false) else { return }
        guard lifetime.isCurrent(token), isValid() else { return }
        let enabled = await feature.isEnabled(accountID: accountID)
        guard lifetime.isCurrent(token), isValid() else { return }
        guard await validate(token: token, requireGrant: false),
              lifetime.isCurrent(token),
              isValid()
        else { return }
        if enabled {
            guard await validate(token: token, requireGrant: true) else { return }
            guard lifetime.isCurrent(token), isValid() else { return }
            await loadPicker(token: token)
        } else {
            phase = .optIn
        }
    }

    private func enableAndAdvance(token: Int) async {
        guard await validate(token: token, requireGrant: false),
              lifetime.isCurrent(token)
        else { return }
        guard isValid() else { return }
        do {
            try await feature.enable(accountID: accountID)
        } catch {
            guard lifetime.isCurrent(token), isValid() else { return }
            errorMessage = Self.genericSaveFailure
            return
        }
        guard lifetime.isCurrent(token),
              await validate(token: token, requireGrant: true)
        else { return }
        guard lifetime.isCurrent(token), isValid() else { return }
        await loadPicker(token: token)
    }

    private func loadPicker(token: Int) async {
        guard await validate(token: token, requireGrant: true)
        else { return }
        guard lifetime.isCurrent(token), isValid() else { return }
        let canPresentPicker = await feature.canPresentPicker(
            accountID: accountID
        )
        guard lifetime.isCurrent(token), isValid() else { return }
        guard canPresentPicker else {
            errorMessage = Self.genericSaveFailure
            return
        }
        guard await validate(token: token, requireGrant: true) else { return }
        guard lifetime.isCurrent(token), isValid(),
              let provider = feature.accessToken
        else { return }
        do {
            let resolved = try await provider(accountID)
            guard lifetime.isCurrent(token),
                  await validate(token: token, requireGrant: true)
            else { return }
            guard lifetime.isCurrent(token), isValid() else { return }
            pickerAccessToken = resolved
            pickerOperationToken = token
            phase = .picking(accessToken: resolved)
        } catch {
            guard lifetime.isCurrent(token), isValid() else { return }
            errorMessage = Self.genericSaveFailure
        }
    }

    private func inspect(_ pick: GoogleDrivePick?, token: Int) async {
        guard let pick, Self.isValidFolder(pick) else {
            guard lifetime.isCurrent(token) else { return }
            errorMessage = GoogleDriveSaveError.invalidFolder.errorDescription
            if let pickerAccessToken {
                pickerOperationToken = token
                phase = .picking(accessToken: pickerAccessToken)
            }
            return
        }
        guard await validate(token: token, requireGrant: true) else { return }
        guard lifetime.isCurrent(token), isValid() else { return }
        guard let filename = payload.filename, payload.isStaged else {
            guard lifetime.isCurrent(token) else { return }
            errorMessage = GoogleDriveSaveError.payloadUnavailable.errorDescription
            return
        }
        guard let files else {
            publish(GoogleDriveSaveError.serviceUnavailable, token: token)
            return
        }
        do {
            let found = try await files.existingFile(
                named: filename,
                inFolderID: pick.id,
                accountID: accountID
            )
            guard lifetime.isCurrent(token),
                  await validate(token: token, requireGrant: true)
            else { return }
            guard lifetime.isCurrent(token), isValid() else { return }
            pendingFolderID = pick.id
            conflict = found
            if let found {
                phase = .conflict(found)
            } else {
                await performUpload(
                    folderID: pick.id,
                    replacing: nil,
                    token: token
                )
            }
        } catch {
            guard lifetime.isCurrent(token), isValid() else { return }
            uploadActive = false
            progress = nil
            if error as? GoogleDriveSaveError == .sourceUnavailable {
                phase = .optIn
                pickerOperationToken = nil
            } else if let pickerAccessToken {
                phase = .picking(accessToken: pickerAccessToken)
                pickerOperationToken = token
            }
            publish(error, token: token)
        }
    }

    private func beginUpload(folderID: String, replacing fileID: String?) {
        lifetime.start { [weak self] token in
            await self?.performUpload(
                folderID: folderID,
                replacing: fileID,
                token: token
            )
        }
    }

    private func performUpload(
        folderID: String,
        replacing fileID: String?,
        token: Int
    ) async {
        guard Self.isValidFolderID(folderID),
              fileID.map({
                  Self.canReplace(
                      conflictID: $0,
                      originalFileID: originalFileID
                  )
              }) ?? true
        else {
            publish(GoogleDriveSaveError.invalidFolder, token: token)
            return
        }
        guard await validate(token: token, requireGrant: true) else { return }
        guard lifetime.isCurrent(token), isValid() else { return }
        phase = .uploading
        do {
            let result = try await executeUpload(
                folderID: folderID,
                replacing: fileID,
                token: token,
                progressHandler: nil
            )
            guard lifetime.isCurrent(token),
                  await validate(token: token, requireGrant: true)
            else { return }
            guard lifetime.isCurrent(token), isValid() else { return }
            finalizeUpload(result, token: token)
        } catch {
            guard lifetime.isCurrent(token), isValid() else { return }
            uploadActive = false
            progress = nil
            if error as? GoogleDriveSaveError == .sourceUnavailable {
                phase = .optIn
                pickerOperationToken = nil
            } else if let pickerAccessToken {
                phase = .picking(accessToken: pickerAccessToken)
                pickerOperationToken = token
            }
            publish(error, token: token)
        }
    }

    private func executeUpload(
        folderID: String,
        replacing fileID: String?,
        token: Int,
        progressHandler: (@Sendable (Int64, Int64) -> Void)?
    ) async throws -> GoogleDriveClient.File {
        guard await validate(token: token, requireGrant: true) else {
            throw GoogleDriveSaveError.sourceUnavailable
        }
        guard lifetime.isCurrent(token), isValid() else {
            throw CancellationError()
        }
        guard let filename = payload.filename,
              let mimeType = payload.mimeType,
              let data = payload.bytes,
              let files,
              lifetime.isCurrent(token)
        else { throw GoogleDriveSaveError.payloadUnavailable }
        uploadActive = true
        let callback: @Sendable (Int64, Int64) -> Void = { [weak self] sent, total in
            guard total > 0 else { return }
            Task { @MainActor in
                guard let self,
                      self.lifetime.isCurrent(token),
                      self.uploadActive,
                      self.isValid()
                else { return }
                self.progress = Double(sent) / Double(total)
                progressHandler?(sent, total)
            }
        }
        let result: GoogleDriveClient.File
        if let fileID {
            result = try await files.update(
                fileID: fileID,
                mimeType: mimeType,
                data: data,
                accountID: accountID,
                onProgress: callback
            )
        } else {
            result = try await files.create(
                name: filename,
                mimeType: mimeType,
                data: data,
                parentFolderID: folderID,
                accountID: accountID,
                onProgress: callback
            )
        }
        guard lifetime.isCurrent(token),
              await validate(token: token, requireGrant: true)
        else { throw CancellationError() }
        guard lifetime.isCurrent(token), isValid() else {
            throw CancellationError()
        }
        uploadActive = false
        progress = 1
        return result
    }

    private func finalizeUpload(
        _ result: GoogleDriveClient.File,
        token: Int
    ) {
        guard lifetime.isCurrent(token), isValid() else { return }
        payload.clear()
        phase = .finished
        lifetime.finish()
        pickerAccessToken = nil
        pickerOperationToken = nil
        pendingFolderID = nil
        conflict = nil
        errorMessage = nil
        onSaved?(result)
    }

    private func validate(token: Int, requireGrant: Bool) async -> Bool {
        guard lifetime.isCurrent(token), isValid() else { return false }
        guard await feature.isEligible(accountID: accountID),
              lifetime.isCurrent(token),
              isValid()
        else { return false }
        guard requireGrant else { return true }
        guard await feature.isEnabled(accountID: accountID),
              lifetime.isCurrent(token),
              isValid()
        else { return false }
        return true
    }

    private func publish(_ error: Error, token: Int) {
        guard lifetime.isCurrent(token),
              isValid(),
              !(error is CancellationError)
        else {
            return
        }
        if let error = error as? GoogleDriveSaveError {
            errorMessage = error.errorDescription
        } else {
            errorMessage = Self.genericSaveFailure
        }
        if case .picking = phase {
            pickerOperationToken = token
        }
    }

    private static var genericSaveFailure: String {
        String(
            localized: "Google Drive could not save this file. Try again.",
            bundle: .module
        )
    }
}

/// Errors that can be shown without exposing provider response details.
enum GoogleDriveSaveError: Error, LocalizedError, Equatable {
    case invalidFolder
    case cannotReplaceSource
    case payloadUnavailable
    case sourceUnavailable
    case serviceUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidFolder:
            String(localized: "Choose a Drive folder before saving.", bundle: .module)
        case .cannotReplaceSource:
            String(localized: "The event attachment can only be saved as a new copy.", bundle: .module)
        case .payloadUnavailable:
            String(localized: "Start the save again to prepare this file.", bundle: .module)
        case .sourceUnavailable:
            String(localized: "The calendar source changed before saving finished.", bundle: .module)
        case .serviceUnavailable:
            String(localized: "Google Drive is unavailable in this session.", bundle: .module)
        }
    }
}
