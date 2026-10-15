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
import Foundation
import Observation

/// Orchestrates the event-attachment save flow (#14).
///
/// The model owns every awaited phase — eligibility, opt-in, access
/// token, Picker authorization, metadata, download or export — so the
/// sheet only renders `phase` and calls synchronous start/cancel
/// actions. Each phase carries the operation token it started with: a
/// cancelled, superseded, or finished flow can neither start the next
/// provider call nor publish state.
@Observable
@MainActor
final class GoogleDriveEventSaveModel {
    /// What the sheet renders. The access token lives in the phase, so
    /// leaving the picker drops it with the rest of the state.
    enum Phase: Equatable {
        case intent
        case optIn
        case picking(accessToken: String)
        case working
        case exportChoice([GoogleDriveExportFormat])
        case saving
        case finished
    }

    let attachment: PIMEventAttachment
    let accountID: BrevAccount.ID
    let feature: GoogleDriveFeature
    let files: (any DriveFileServing)?
    /// The staged bytes, shared by reference with the save sheet.
    let payload: GoogleDriveStagedPayload
    var isValid: () -> Bool

    private(set) var phase: Phase = .intent
    private(set) var errorMessage: String?
    /// The file ID Google's Picker authorized for this operation.
    private(set) var authorizedFileID: String?
    private(set) var pickerOperationToken: Int?
    private var metadata: GoogleDriveClient.File?
    private var pickerAccessToken: String?
    private let lifetime = GoogleDriveOperationLifetime()

    init(
        attachment: PIMEventAttachment,
        accountID: BrevAccount.ID,
        feature: GoogleDriveFeature,
        files: (any DriveFileServing)? = nil,
        payload: GoogleDriveStagedPayload? = nil,
        isValid: @escaping () -> Bool = { true }
    ) {
        self.attachment = attachment
        self.accountID = accountID
        self.feature = feature
        self.files = files ?? feature.files
        self.payload = payload ?? GoogleDriveStagedPayload()
        self.isValid = isValid
    }

    // MARK: - Link parsing

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

    // MARK: - View actions

    /// Explicit save intent: resolves eligibility, then opt-in or picker.
    func start() {
        errorMessage = nil
        lifetime.start { [weak self] token in
            await self?.begin(token: token)
        }
    }

    /// Runs the Drive opt-in for this operation and continues on success.
    func enable() {
        lifetime.start { [weak self] token in
            await self?.runEnable(token: token)
        }
    }

    /// Handles a Picker result: authorizes the exact file, then prepares.
    func picked(_ picks: [GoogleDrivePick], pickerToken: Int? = nil) {
        guard let pickerToken = pickerToken ?? pickerOperationToken,
              lifetime.isCurrent(pickerToken),
              isValid()
        else { return }
        pickerOperationToken = nil
        phase = .working
        lifetime.start { [weak self] token in
            await self?.handlePick(picks.first, token: token)
        }
    }

    /// Prepares the bytes using one explicitly chosen export format.
    func chooseExport(_ format: GoogleDriveExportFormat) {
        lifetime.start { [weak self] token in
            await self?.stage(exportFormat: format, token: token)
        }
    }

    /// Records a Picker failure without provider detail.
    func reportPickerFailure(pickerToken: Int? = nil) {
        guard let token = pickerToken ?? pickerOperationToken,
              token == pickerOperationToken,
              lifetime.isCurrent(token),
              isValid()
        else { return }
        lifetime.cancel()
        payload.clear()
        metadata = nil
        authorizedFileID = nil
        pickerAccessToken = nil
        pickerOperationToken = nil
        errorMessage = Self.genericPreparationFailure
        phase = .intent
    }

    /// Ends the flow for good and drops everything staged for it.
    func cancel() {
        lifetime.finish()
        payload.clear()
        metadata = nil
        authorizedFileID = nil
        pickerAccessToken = nil
        pickerOperationToken = nil
        errorMessage = nil
        phase = .finished
    }

    // MARK: - Orchestration

    /// Resolves intent, eligibility, and the grant. Testable directly.
    func begin(token: Int? = nil) async {
        guard let token = token ?? lifetime.nextToken() else { return }
        guard Self.fileID(in: attachment.url) != nil else {
            publish(GoogleDriveEventSaveError.unsupportedLink, token: token)
            return
        }
        guard await validate(token: token, requireGrant: false) else { return }
        guard lifetime.isCurrent(token), isValid() else { return }
        let enabled = await feature.isEnabled(accountID: accountID)
        guard lifetime.isCurrent(token), isValid() else { return }
        guard await validate(token: token, requireGrant: false),
              lifetime.isCurrent(token),
              isValid()
        else { return }
        if enabled {
            guard await validate(token: token, requireGrant: true) else {
                return
            }
            await loadPicker(token: token)
        } else {
            phase = .optIn
        }
    }

    /// Authorizes a Picker result against the current operation.
    @discardableResult
    func authorize(pick: GoogleDrivePick?, token: Int? = nil) async -> Bool {
        guard let token = token ?? lifetime.nextToken() else { return false }
        guard await validate(token: token, requireGrant: true) else {
            guard lifetime.isCurrent(token), isValid() else { return false }
            errorMessage = GoogleDriveEventSaveError
                .pickerAuthorizationRequired.errorDescription
            authorizedFileID = nil
            phase = .optIn
            pickerOperationToken = nil
            return false
        }
        guard lifetime.isCurrent(token), isValid() else { return false }
        guard let pick,
              let expected = Self.fileID(in: attachment.url),
              pick.id == expected
        else {
            publish(GoogleDriveEventSaveError.mismatchedFile, token: token)
            return false
        }
        authorizedFileID = expected
        return true
    }

    /// Reads metadata for the authorized file and validates the result.
    func loadMetadata(token: Int? = nil) async throws -> GoogleDriveClient.File {
        guard let token = token ?? lifetime.nextToken() else {
            throw CancellationError()
        }
        guard let fileID = Self.fileID(in: attachment.url) else {
            throw GoogleDriveEventSaveError.unsupportedLink
        }
        guard authorizedFileID == fileID else {
            throw GoogleDriveEventSaveError.pickerAuthorizationRequired
        }
        guard await validate(token: token, requireGrant: true) else {
            throw GoogleDriveEventSaveError.sourceUnavailable
        }
        guard lifetime.isCurrent(token), isValid() else {
            throw CancellationError()
        }
        guard let files else {
            throw GoogleDriveEventSaveError.serviceUnavailable
        }
        let file = try await files.metadata(
            fileID: fileID,
            accountID: accountID
        )
        guard lifetime.isCurrent(token),
              await validate(token: token, requireGrant: true)
        else { throw CancellationError() }
        guard lifetime.isCurrent(token), isValid() else {
            throw CancellationError()
        }
        guard file.id == fileID else {
            throw GoogleDriveEventSaveError.mismatchedFile
        }
        try Self.validateDownloadable(file)
        metadata = file
        return file
    }

    /// Downloads or exports the authorized file into the shared payload.
    func prepare(
        exportFormat: GoogleDriveExportFormat? = nil,
        token: Int? = nil
    ) async throws {
        guard let token = token ?? lifetime.nextToken() else {
            throw CancellationError()
        }
        guard let fileID = Self.fileID(in: attachment.url) else {
            throw GoogleDriveEventSaveError.unsupportedLink
        }
        guard authorizedFileID == fileID else {
            throw GoogleDriveEventSaveError.pickerAuthorizationRequired
        }
        // Metadata read during authorization is reused; a flow that
        // starts at prepare reads it once here.
        let file: GoogleDriveClient.File
        if let metadata, metadata.id == fileID {
            file = metadata
            guard await validate(token: token, requireGrant: true) else {
                throw GoogleDriveEventSaveError.sourceUnavailable
            }
            guard lifetime.isCurrent(token), isValid() else {
                throw CancellationError()
            }
        } else {
            file = try await loadMetadata(token: token)
            guard lifetime.isCurrent(token), isValid() else {
                throw CancellationError()
            }
        }
        if file.isWorkspaceDocument {
            guard let exportFormat,
                  GoogleDriveExportFormats.options(for: file.mimeType)
                  .contains(exportFormat)
            else { throw GoogleDriveEventSaveError.exportChoiceRequired }
            guard let files else {
                throw GoogleDriveEventSaveError.serviceUnavailable
            }
            guard await validate(token: token, requireGrant: true),
                  lifetime.isCurrent(token),
                  isValid()
            else { throw CancellationError() }
            let data = try await files.export(
                fileID: fileID,
                mimeType: exportFormat.mimeType,
                accountID: accountID
            )
            guard lifetime.isCurrent(token),
                  await validate(token: token, requireGrant: true)
            else { throw CancellationError() }
            guard lifetime.isCurrent(token), isValid() else {
                throw CancellationError()
            }
            payload.stage(
                filename: GoogleDriveExportFormats.exportedFilename(
                    for: file.name,
                    format: exportFormat
                ),
                mimeType: exportFormat.mimeType,
                bytes: data,
                sourceFileID: fileID
            )
            return
        }
        guard let files else {
            throw GoogleDriveEventSaveError.serviceUnavailable
        }
        guard await validate(token: token, requireGrant: true),
              lifetime.isCurrent(token),
              isValid()
        else { throw CancellationError() }
        let data = try await files.download(
            fileID: fileID,
            accountID: accountID
        )
        guard lifetime.isCurrent(token),
              await validate(token: token, requireGrant: true)
        else { throw CancellationError() }
        guard lifetime.isCurrent(token), isValid() else {
            throw CancellationError()
        }
        payload.stage(
            filename: file.name,
            mimeType: file.mimeType,
            bytes: data,
            sourceFileID: fileID
        )
    }

    private func runEnable(token: Int) async {
        guard await validate(token: token, requireGrant: false),
              lifetime.isCurrent(token),
              isValid()
        else { return }
        do {
            try await feature.enable(accountID: accountID)
        } catch {
            guard lifetime.isCurrent(token), isValid() else { return }
            errorMessage = Self.genericEnableFailure
            return
        }
        guard await validate(token: token, requireGrant: false),
              lifetime.isCurrent(token),
              isValid()
        else { return }
        let enabled = await feature.isEnabled(accountID: accountID)
        guard lifetime.isCurrent(token), isValid(), enabled else { return }
        guard lifetime.isCurrent(token), isValid() else { return }
        await loadPicker(token: token)
    }

    private func loadPicker(token: Int) async {
        guard await validate(token: token, requireGrant: true) else { return }
        guard lifetime.isCurrent(token), isValid() else { return }
        let canPresentPicker = await feature.canPresentPicker(
            accountID: accountID
        )
        guard lifetime.isCurrent(token), isValid() else { return }
        guard canPresentPicker else {
            guard lifetime.isCurrent(token) else { return }
            errorMessage = String(
                localized: "The Google picker is not configured in this build.",
                bundle: .module
            )
            return
        }
        guard await validate(token: token, requireGrant: true) else { return }
        guard lifetime.isCurrent(token), isValid(),
              let provider = feature.accessToken
        else { return }
        do {
            let resolved = try await provider(accountID)
            // The token is only adopted once it still belongs to this
            // operation and the source/grant are unchanged.
            guard lifetime.isCurrent(token),
                  await validate(token: token, requireGrant: true)
            else { return }
            guard lifetime.isCurrent(token), isValid() else { return }
            pickerOperationToken = token
            pickerAccessToken = resolved
            phase = .picking(accessToken: resolved)
        } catch {
            guard lifetime.isCurrent(token), isValid() else { return }
            errorMessage = String(
                localized: "Google Drive could not authorize this file.",
                bundle: .module
            )
        }
    }

    private func handlePick(
        _ pick: GoogleDrivePick?,
        token: Int
    ) async {
        guard await authorize(pick: pick, token: token) else { return }
        guard lifetime.isCurrent(token), isValid() else { return }
        do {
            let file = try await loadMetadata(token: token)
            guard lifetime.isCurrent(token), isValid() else { return }
            if file.isWorkspaceDocument {
                let formats = GoogleDriveExportFormats.options(
                    for: file.mimeType
                )
                guard !formats.isEmpty else {
                    throw GoogleDriveEventSaveError.unsupportedFile
                }
                phase = .exportChoice(formats)
            } else {
                await stage(exportFormat: nil, token: token)
            }
        } catch {
            publish(error, token: token)
        }
    }

    private func stage(
        exportFormat: GoogleDriveExportFormat?,
        token: Int
    ) async {
        do {
            try await prepare(exportFormat: exportFormat, token: token)
            guard lifetime.isCurrent(token),
                  await validate(token: token, requireGrant: true)
            else { return }
            guard lifetime.isCurrent(token), isValid() else { return }
            errorMessage = nil
            phase = .saving
        } catch {
            publish(error, token: token)
        }
    }

    /// Re-reads the live source, eligibility, and grant around an await.
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

    /// Only Brev's own typed errors reach the user; anything else —
    /// including provider `LocalizedError` text — maps to a fallback.
    private func publish(_ error: Error, token: Int) {
        guard lifetime.isCurrent(token), isValid() else { return }
        if error is CancellationError { return }
        if let saveError = error as? GoogleDriveEventSaveError {
            errorMessage = saveError.errorDescription
        } else {
            errorMessage = Self.genericPreparationFailure
        }
        if let pickerAccessToken {
            phase = .picking(accessToken: pickerAccessToken)
            pickerOperationToken = token
        }
    }

    private static var genericPreparationFailure: String {
        String(
            localized: "Google Drive could not prepare this file.",
            bundle: .module
        )
    }

    private static var genericEnableFailure: String {
        String(
            localized: "Google Drive could not be enabled for this account.",
            bundle: .module
        )
    }

    /// The event flow's own allowlist: folders, shortcuts, and Google
    /// types Brev cannot export are rejected here, not globally.
    private static func validateDownloadable(
        _ metadata: GoogleDriveClient.File
    ) throws {
        guard metadata.mimeType != "application/vnd.google-apps.folder",
              !metadata.isShortcut
        else { throw GoogleDriveEventSaveError.unsupportedFile }
        guard !metadata.isWorkspaceDocument
            || !GoogleDriveExportFormats.options(for: metadata.mimeType)
            .isEmpty
        else { throw GoogleDriveEventSaveError.unsupportedFile }
    }
}

enum GoogleDriveEventSaveError: Error, LocalizedError, Equatable {
    case unsupportedLink
    case unsupportedFile
    case exportChoiceRequired
    case mismatchedFile
    case pickerAuthorizationRequired
    case sourceUnavailable
    case serviceUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedLink:
            String(localized: "This attachment is not a supported Google Drive link.", bundle: .module)
        case .unsupportedFile:
            String(
                localized: "Folders, shortcuts, and unsupported Google file types cannot be saved as attachments.",
                bundle: .module
            )
        case .exportChoiceRequired:
            String(localized: "Choose an export format before saving this Google document.", bundle: .module)
        case .mismatchedFile:
            String(localized: "Choose the same file as the event attachment.", bundle: .module)
        case .pickerAuthorizationRequired:
            String(localized: "Confirm the attachment in Google's picker before saving.", bundle: .module)
        case .sourceUnavailable:
            String(localized: "The calendar source changed before saving finished.", bundle: .module)
        case .serviceUnavailable:
            String(localized: "Google Drive is unavailable in this session.", bundle: .module)
        }
    }
}
