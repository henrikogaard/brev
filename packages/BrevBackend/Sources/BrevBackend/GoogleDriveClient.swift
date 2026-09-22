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

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Google Drive REST client for the opt-in attachment flows (#14).
///
/// The client only supports the operations the attachment workflows
/// need: file metadata, byte download, Google Workspace export, and
/// multipart upload into a chosen folder. It deliberately does not
/// offer browsing — the `drive.file` scope only covers files the
/// user picks through the Google Picker or files Brev itself created,
/// which is the privacy boundary ADR-0006 documents.
///
/// Every call takes the account's access token explicitly so the
/// client stays stateless; the session resolves tokens through the
/// shared Google grant (the same path PIM features ride).
public struct GoogleDriveClient: Sendable {
    /// The `drive.file` scope — the narrowest grant that covers
    /// picking and saving user-selected files. Requested only when the
    /// user invokes a Drive action and confirms the opt-in.
    public static let scope =
        "https://www.googleapis.com/auth/drive.file"

    /// Errors surfaced by the Drive path.
    public enum DriveError: Error, Sendable, Hashable, LocalizedError {
        /// The credential was rejected or lacks the `drive.file`
        /// scope — the UI should re-run the opt-in.
        case authenticationRequired
        /// The file is gone or outside the grant's coverage.
        case notFound
        /// The provider answered with a status or body Brev cannot use.
        case invalidResponse
        /// Connectivity or an unspecified transport failure.
        case transportFailed
        /// The workspace file has no export format for the request.
        case exportUnsupported

        public var errorDescription: String? {
            switch self {
            case .authenticationRequired:
                String(
                    localized:
                    "Google Drive needs a fresh grant. Enable Drive again from the attachment menu.",
                    bundle: .module
                )
            case .notFound:
                String(
                    localized:
                    "That Drive file is no longer available to Brev.",
                    bundle: .module
                )
            case .invalidResponse:
                String(
                    localized:
                    "Google Drive returned a response Brev could not use.",
                    bundle: .module
                )
            case .transportFailed:
                String(
                    localized:
                    "Google Drive could not be reached. Check the connection and try again.",
                    bundle: .module
                )
            case .exportUnsupported:
                String(
                    localized:
                    "This Google file cannot be exported as an attachment.",
                    bundle: .module
                )
            }
        }
    }

    /// Drive file metadata the attachment flows consume.
    public struct File: Sendable, Hashable {
        public let id: String
        public let name: String
        public let mimeType: String
        /// Byte size for binary files; nil for workspace documents.
        public let sizeBytes: Int64?
        /// The Drive web link used by the attach-as-link flow.
        public let webViewLink: String?

        public init(
            id: String,
            name: String,
            mimeType: String,
            sizeBytes: Int64? = nil,
            webViewLink: String? = nil
        ) {
            self.id = id
            self.name = name
            self.mimeType = mimeType
            self.sizeBytes = sizeBytes
            self.webViewLink = webViewLink
        }

        /// Whether the file is a Google Workspace document that must be
        /// exported rather than downloaded.
        public var isWorkspaceDocument: Bool {
            mimeType.hasPrefix("application/vnd.google-apps.")
                && mimeType != "application/vnd.google-apps.folder"
        }
    }

    /// The transport seam — tests inject a stubbed sender.
    public typealias Transport =
        @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private static let apiBase = "https://www.googleapis.com/drive/v3"
    private static let uploadBase =
        "https://www.googleapis.com/upload/drive/v3"
    /// Metadata fields every files.get/create response carries.
    private static let fileFields =
        "id,name,mimeType,size,webViewLink"

    private let transport: Transport

    public init(
        transport: @escaping Transport = { request in
            let (data, response) = try await URLSession.shared.data(
                for: request
            )
            guard let http = response as? HTTPURLResponse else {
                throw DriveError.invalidResponse
            }
            return (data, http)
        }
    ) {
        self.transport = transport
    }

    // MARK: - Reads

    /// Metadata for one file the grant covers.
    public func metadata(
        fileID: String,
        accessToken: String
    ) async throws -> File {
        var components = URLComponents(
            string: Self.apiBase + "/files/" + Self.encode(fileID)
        )
        components?.queryItems = [
            URLQueryItem(name: "fields", value: Self.fileFields),
        ]
        guard let url = components?.url else {
            throw DriveError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue(
            "Bearer " + accessToken, forHTTPHeaderField: "Authorization"
        )
        let (data, response) = try await send(request)
        return try decode(File.self, data: data, response: response)
    }

    /// Downloads a binary file's bytes. Workspace documents must go
    /// through `export` instead — this call fails for them.
    public func download(
        fileID: String,
        accessToken: String
    ) async throws -> Data {
        var components = URLComponents(
            string: Self.apiBase + "/files/" + Self.encode(fileID)
        )
        components?.queryItems = [
            URLQueryItem(name: "alt", value: "media"),
        ]
        guard let url = components?.url else {
            throw DriveError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue(
            "Bearer " + accessToken, forHTTPHeaderField: "Authorization"
        )
        let (data, response) = try await send(request)
        try expectSuccess(response)
        return data
    }

    /// Exports a Google Workspace document into a concrete MIME type.
    public func export(
        fileID: String,
        mimeType: String,
        accessToken: String
    ) async throws -> Data {
        var components = URLComponents(
            string:
            Self.apiBase + "/files/" + Self.encode(fileID) + "/export"
        )
        components?.queryItems = [
            URLQueryItem(name: "mimeType", value: mimeType),
        ]
        guard let url = components?.url else {
            throw DriveError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue(
            "Bearer " + accessToken, forHTTPHeaderField: "Authorization"
        )
        let (data, response) = try await send(request)
        if response.statusCode == 400 || response.statusCode == 403 {
            // Google answers 400/403 when the type has no export for
            // the requested format.
            throw DriveError.exportUnsupported
        }
        try expectSuccess(response)
        return data
    }

    // MARK: - Writes

    /// Uploads bytes into the chosen folder as a new file.
    ///
    /// Multipart upload keeps metadata and bytes in one request; the
    /// response carries the created file's metadata. `drive.file`
    /// covers files Brev creates, so no extra scope is needed.
    @discardableResult
    public func create(
        name: String,
        mimeType: String,
        data: Data,
        parentFolderID: String?,
        accessToken: String
    ) async throws -> File {
        var metadata: [String: Any] = ["name": name]
        if let parentFolderID {
            metadata["parents"] = [parentFolderID]
        }
        let boundary = "brev-" + UUID().uuidString
        var body = Data()
        body.append(Self.multipartBoundaryLine(boundary))
        body.append(Data(
            "Content-Type: application/json; charset=UTF-8\r\n\r\n"
                .utf8
        ))
        try body.append(JSONSerialization.data(withJSONObject: metadata))
        body.append(Self.multipartBoundaryLine(boundary))
        body.append(Data(
            ("Content-Type: " + mimeType + "\r\n\r\n").utf8
        ))
        body.append(data)
        body.append(Data(
            ("\r\n--" + boundary + "--\r\n").utf8
        ))

        var components = URLComponents(
            string: Self.uploadBase + "/files"
        )
        components?.queryItems = [
            URLQueryItem(name: "uploadType", value: "multipart"),
            URLQueryItem(name: "fields", value: Self.fileFields),
        ]
        guard let url = components?.url else {
            throw DriveError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "Bearer " + accessToken, forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "multipart/related; boundary=" + boundary,
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = body
        let (responseData, response) = try await send(request)
        return try decode(File.self, data: responseData, response: response)
    }

    /// Whether a Brev-created file with this name already exists in the
    /// folder — the save flow's conflict check. `drive.file` only
    /// lists files Brev created or the user opened, so a miss does not
    /// prove the folder lacks a same-named user file.
    public func existingFile(
        named name: String,
        inFolderID folderID: String?,
        accessToken: String
    ) async throws -> File? {
        var query = "name = '" + Self.escapeQueryLiteral(name) + "'"
            + " and trashed = false"
        if let folderID {
            query += " and '" + Self.escapeQueryLiteral(folderID)
                + "' in parents"
        }
        var components = URLComponents(
            string: Self.apiBase + "/files"
        )
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(
                name: "fields",
                value: "files(" + Self.fileFields + ")"
            ),
            URLQueryItem(name: "pageSize", value: "1"),
        ]
        guard let url = components?.url else {
            throw DriveError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue(
            "Bearer " + accessToken, forHTTPHeaderField: "Authorization"
        )
        let (data, response) = try await send(request)
        struct ListResponse: Decodable {
            let files: [File]?
        }
        let list = try decode(ListResponse.self, data: data, response: response)
        return list.files?.first
    }

    /// Overwrites the bytes of a file Brev owns — the save flow's
    /// "Replace existing" path. The name is preserved; only content
    /// and MIME type change.
    @discardableResult
    public func update(
        fileID: String,
        mimeType: String,
        data: Data,
        accessToken: String
    ) async throws -> File {
        let boundary = "brev-" + UUID().uuidString
        var body = Data()
        body.append(Self.multipartBoundaryLine(boundary))
        body.append(Data(
            "Content-Type: application/json; charset=UTF-8\r\n\r\n"
                .utf8
        ))
        body.append(Data("{}".utf8))
        body.append(Self.multipartBoundaryLine(boundary))
        body.append(Data(
            ("Content-Type: " + mimeType + "\r\n\r\n").utf8
        ))
        body.append(data)
        body.append(Data(
            ("\r\n--" + boundary + "--\r\n").utf8
        ))

        var components = URLComponents(
            string: Self.uploadBase + "/files/" + Self.encode(fileID)
        )
        components?.queryItems = [
            URLQueryItem(name: "uploadType", value: "multipart"),
            URLQueryItem(name: "fields", value: Self.fileFields),
        ]
        guard let url = components?.url else {
            throw DriveError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue(
            "Bearer " + accessToken, forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "multipart/related; boundary=" + boundary,
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = body
        let (responseData, response) = try await send(request)
        return try decode(File.self, data: responseData, response: response)
    }

    // MARK: - Internals

    private func send(
        _ request: URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport(request)
        } catch let error as DriveError {
            throw error
        } catch {
            throw DriveError.transportFailed
        }
    }

    private func expectSuccess(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200 ..< 300:
            return
        case 401, 403:
            throw DriveError.authenticationRequired
        case 404:
            throw DriveError.notFound
        default:
            throw DriveError.invalidResponse
        }
    }

    private func decode<T: Decodable>(
        _ type: T.Type,
        data: Data,
        response: HTTPURLResponse
    ) throws -> T {
        try expectSuccess(response)
        do {
            return try JSONDecoder.drive.decode(type, from: data)
        } catch {
            throw DriveError.invalidResponse
        }
    }

    /// RFC 3986 path-component encoding for file IDs.
    static func encode(_ value: String) -> String {
        value.utf8.reduce(into: String()) { result, byte in
            let unreserved =
                (byte >= 0x41 && byte <= 0x5A)
                    || (byte >= 0x61 && byte <= 0x7A)
                    || (byte >= 0x30 && byte <= 0x39)
                    || byte == 0x2D || byte == 0x2E
                    || byte == 0x5F || byte == 0x7E
            if unreserved {
                result.append(Character(UnicodeScalar(byte)))
            } else {
                result += String(format: "%%%02X", byte)
            }
        }
    }

    /// Escapes a single-quoted Drive query literal.
    static func escapeQueryLiteral(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
    }

    private static func multipartBoundaryLine(
        _ boundary: String
    ) -> Data {
        Data(("--" + boundary + "\r\n").utf8)
    }
}

extension GoogleDriveClient.File: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, name, mimeType, size, webViewLink
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sizeString = try container.decodeIfPresent(
            String.self, forKey: .size
        )
        try self.init(
            id: container.decode(String.self, forKey: .id),
            name: container.decode(String.self, forKey: .name),
            mimeType: container.decode(String.self, forKey: .mimeType),
            sizeBytes: sizeString.flatMap(Int64.init),
            webViewLink: container.decodeIfPresent(
                String.self, forKey: .webViewLink
            )
        )
    }
}

private extension JSONDecoder {
    static let drive = JSONDecoder()
}
