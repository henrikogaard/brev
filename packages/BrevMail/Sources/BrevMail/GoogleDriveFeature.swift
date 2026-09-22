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

/// The file operations the Drive attachment flows need (#14).
/// `GoogleDriveClient` conforms; tests substitute a recording
/// double so the view layer never touches the network.
public protocol DriveFileServing: Sendable {
    /// Metadata for one file the account's grant covers.
    func metadata(
        fileID: String,
        accountID: BrevAccount.ID
    ) async throws -> GoogleDriveClient.File
    /// Downloads a binary file's bytes.
    func download(
        fileID: String,
        accountID: BrevAccount.ID
    ) async throws -> Data
    /// Exports a workspace document into a concrete MIME type.
    func export(
        fileID: String,
        mimeType: String,
        accountID: BrevAccount.ID
    ) async throws -> Data
    /// Uploads bytes into the chosen folder as a new file.
    @discardableResult
    func create(
        name: String,
        mimeType: String,
        data: Data,
        parentFolderID: String?,
        accountID: BrevAccount.ID
    ) async throws -> GoogleDriveClient.File
    /// Whether a Brev-created file with this name already exists in the
    /// folder — the save flow's conflict check.
    func existingFile(
        named name: String,
        inFolderID folderID: String?,
        accountID: BrevAccount.ID
    ) async throws -> GoogleDriveClient.File?
    /// Overwrites the bytes of a file Brev owns — the save flow's
    /// "Replace existing" path.
    @discardableResult
    func update(
        fileID: String,
        mimeType: String,
        data: Data,
        accountID: BrevAccount.ID
    ) async throws -> GoogleDriveClient.File
}

/// Adapts the stateless `GoogleDriveClient` to the account-scoped
/// seam by resolving the account's access token per call.
public struct GoogleDriveFileService: DriveFileServing {
    private let client: GoogleDriveClient
    private let accessToken: @Sendable (BrevAccount.ID) async throws -> String

    public init(
        client: GoogleDriveClient = GoogleDriveClient(),
        accessToken: @escaping @Sendable (BrevAccount.ID) async throws -> String
    ) {
        self.client = client
        self.accessToken = accessToken
    }

    public func metadata(
        fileID: String,
        accountID: BrevAccount.ID
    ) async throws -> GoogleDriveClient.File {
        try await client.metadata(
            fileID: fileID,
            accessToken: accessToken(accountID)
        )
    }

    public func download(
        fileID: String,
        accountID: BrevAccount.ID
    ) async throws -> Data {
        try await client.download(
            fileID: fileID,
            accessToken: accessToken(accountID)
        )
    }

    public func export(
        fileID: String,
        mimeType: String,
        accountID: BrevAccount.ID
    ) async throws -> Data {
        try await client.export(
            fileID: fileID,
            mimeType: mimeType,
            accessToken: accessToken(accountID)
        )
    }

    @discardableResult
    public func create(
        name: String,
        mimeType: String,
        data: Data,
        parentFolderID: String?,
        accountID: BrevAccount.ID
    ) async throws -> GoogleDriveClient.File {
        try await client.create(
            name: name,
            mimeType: mimeType,
            data: data,
            parentFolderID: parentFolderID,
            accessToken: accessToken(accountID)
        )
    }

    public func existingFile(
        named name: String,
        inFolderID folderID: String?,
        accountID: BrevAccount.ID
    ) async throws -> GoogleDriveClient.File? {
        try await client.existingFile(
            named: name,
            inFolderID: folderID,
            accessToken: accessToken(accountID)
        )
    }

    @discardableResult
    public func update(
        fileID: String,
        mimeType: String,
        data: Data,
        accountID: BrevAccount.ID
    ) async throws -> GoogleDriveClient.File {
        try await client.update(
            fileID: fileID,
            mimeType: mimeType,
            data: data,
            accessToken: accessToken(accountID)
        )
    }
}

/// Observable owner of the Google Drive attachment feature (#14).
///
/// Drive stays disabled until the user invokes a Drive action; the
/// first invocation runs the account's OAuth re-authorization with the
/// `drive.file` scope unioned into the grant — the same verified
/// swap the PIM feature enablement uses, so a declined or partial
/// grant changes nothing. Enablement state is read from the account's
/// stored granted scopes, never a separate flag, so revoking the grant
/// outside Brev degrades the feature honestly on the next call.
@Observable
@MainActor
public final class GoogleDriveFeature {
    /// Whether an opt-in authorization is in flight.
    public private(set) var isEnabling = false
    /// Last actionable failure, surfaced inline by the sheets.
    public private(set) var lastError: String?

    private let configuration:
        @Sendable (BrevAccount.ID) async -> GoogleOAuthAccountConfiguration?
    private let enablement:
        ((BrevAccount.ID) async throws -> Void)?
    /// Resolves the account's raw access token for the Google-hosted
    /// picker page; nil when the session has no Google token provider.
    public let accessToken:
        (@Sendable (BrevAccount.ID) async throws -> String)?
    /// The account-scoped file operations; nil when the session has no
    /// Google token provider (demo mode, IMAP-only).
    public let files: (any DriveFileServing)?
    /// The picker credentials Tuist injects from the build environment;
    /// empty when the build has no Google API key configured.
    public let pickerDeveloperKey: String
    public let pickerAppID: String

    public init(
        configuration: @escaping @Sendable (BrevAccount.ID) async -> GoogleOAuthAccountConfiguration?,
        enablement: ((BrevAccount.ID) async throws -> Void)? = nil,
        accessToken: (@Sendable (BrevAccount.ID) async throws -> String)? = nil,
        files: (any DriveFileServing)? = nil,
        pickerDeveloperKey: String = "",
        pickerAppID: String = ""
    ) {
        self.configuration = configuration
        self.enablement = enablement
        self.accessToken = accessToken
        self.files = files
        self.pickerDeveloperKey = pickerDeveloperKey
        self.pickerAppID = pickerAppID
    }

    /// Whether the account is a Gmail API account — the only accounts
    /// Drive can attach to. Non-Google accounts never see the actions.
    public func isEligible(account: BrevAccount) -> Bool {
        account.backendIdentifier == BrevAccount.gmailAPIBackendIdentifier
    }

    /// Whether the account's stored grant already covers
    /// `drive.file`. Reads the persisted configuration each call so
    /// a revoked or re-scoped grant is reflected immediately.
    public func isEnabled(accountID: BrevAccount.ID) async -> Bool {
        await configuration(accountID)?.grantedScopes
            .contains(GoogleDriveClient.scope) == true
    }

    /// Whether the picker can render — the OAuth grant plus the
    /// developer key and app ID the Picker API requires.
    public func canPresentPicker(accountID: BrevAccount.ID) async -> Bool {
        await isEnabled(accountID: accountID)
            && !pickerDeveloperKey.isEmpty
            && !pickerAppID.isEmpty
    }

    /// Runs the Drive opt-in: a fresh OAuth authorization that unions
    /// `drive.file` into the account's grant. Cancellation or a
    /// partial grant throws before anything is stored.
    public func enable(accountID: BrevAccount.ID) async throws {
        isEnabling = true
        defer { isEnabling = false }
        do {
            guard let enablement else {
                throw MailBackendError.backendSpecific(
                    message: String(
                        localized:
                        "Google Drive is unavailable in this session.",
                        bundle: .module
                    )
                )
            }
            try await enablement(accountID)
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            throw error
        }
    }
}
