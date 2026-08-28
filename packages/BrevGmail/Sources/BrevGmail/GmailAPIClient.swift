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

/// The response representation requested from `users.messages.get` and
/// `users.threads.get`.
public enum GmailMessageFormat: String, Sendable, Equatable {
    /// IDs and labels only.
    case minimal
    /// IDs, labels, and selected headers.
    case metadata
    /// Parsed MIME payload.
    case full
    /// Base64url-encoded RFC 2822 source.
    case raw
}

/// History record categories accepted by Gmail's `history.list` endpoint.
public enum GmailHistoryType: String, Sendable, Equatable {
    /// A message was added to the mailbox.
    case messageAdded
    /// A message was deleted from the mailbox.
    case messageDeleted
    /// Labels were added to a message.
    case labelAdded
    /// Labels were removed from a message.
    case labelRemoved
}

/// The typed operations needed by the Gmail synchronization foundation.
public protocol GmailAPIClientProtocol: Sendable {
    /// Fetches the authenticated mailbox profile.
    func getProfile() async throws -> GmailProfile
    /// Lists the mailbox label catalog.
    func listLabels() async throws -> [GmailLabel]
    /// Fetches one label by immutable Gmail ID.
    func getLabel(id: String) async throws -> GmailLabel
    /// Lists message references, optionally filtered by labels or Gmail query.
    func listMessages(
        maxResults: Int,
        pageToken: String?,
        labelIDs: [String],
        query: String?,
        includeSpamTrash: Bool
    ) async throws -> GmailMessagePage
    /// Fetches one message detail response.
    func getMessage(
        id: String,
        format: GmailMessageFormat,
        metadataHeaders: [String]
    ) async throws -> GmailMessage
    /// Fetches one attachment body.
    func getAttachment(messageID: String, attachmentID: String) async throws -> GmailAttachment
    /// Lists chronological mailbox history after a cursor.
    func listHistory(
        startHistoryID: String,
        maxResults: Int,
        pageToken: String?,
        labelID: String?,
        historyTypes: [GmailHistoryType]
    ) async throws -> GmailHistoryPage
    /// Adds and removes labels on one message.
    func modifyMessageLabels(
        id: String,
        addLabelIDs: [String],
        removeLabelIDs: [String]
    ) async throws -> GmailMessage
    /// Adds and removes labels on every message in one thread.
    func modifyThreadLabels(
        id: String,
        addLabelIDs: [String],
        removeLabelIDs: [String]
    ) async throws -> GmailThread
    /// Moves one message to Trash.
    func trashMessage(id: String) async throws -> GmailMessage
    /// Restores one message from Trash.
    func untrashMessage(id: String) async throws -> GmailMessage
    /// Permanently deletes one message.
    func deleteMessage(id: String) async throws
    /// Moves one thread to Trash.
    func trashThread(id: String) async throws -> GmailThread
    /// Restores one thread from Trash.
    func untrashThread(id: String) async throws -> GmailThread
    /// Permanently deletes one thread.
    func deleteThread(id: String) async throws
    /// Applies label changes to up to 1,000 messages.
    func batchModifyMessageLabels(
        messageIDs: [String],
        addLabelIDs: [String],
        removeLabelIDs: [String]
    ) async throws
    /// Creates a user label.
    func createLabel(_ label: GmailLabelWrite) async throws -> GmailLabel
    /// Patches a user label.
    func patchLabel(id: String, with label: GmailLabelWrite) async throws -> GmailLabel
    /// Permanently deletes a user label.
    func deleteLabel(id: String) async throws
    /// Creates a draft from RFC 2822 source.
    func createDraft(rawMIME: String, threadID: String?) async throws -> GmailDraft
    /// Replaces a draft's RFC 2822 source.
    func updateDraft(id: String, rawMIME: String, threadID: String?) async throws -> GmailDraft
    /// Permanently deletes a draft.
    func deleteDraft(id: String) async throws
    /// Sends an existing draft.
    func sendDraft(id: String) async throws -> GmailMessage
    /// Sends an RFC 2822 message and returns Gmail's created message.
    func sendMessage(rawMIME: String, threadID: String?) async throws -> GmailMessage
    /// Lists configured send-as identities and signature/default metadata.
    func listSendAs() async throws -> [GmailSendAs]
}

public extension GmailAPIClientProtocol {
    func modifyMessageLabels(id: String, addLabelIDs: [String],
                             removeLabelIDs: [String]) async throws -> GmailMessage { throw GmailAPIError.invalidRequest }
    func modifyThreadLabels(id: String, addLabelIDs: [String],
                            removeLabelIDs: [String]) async throws -> GmailThread { throw GmailAPIError.invalidRequest }
    func trashMessage(id: String) async throws -> GmailMessage { throw GmailAPIError.invalidRequest }
    func untrashMessage(id: String) async throws -> GmailMessage { throw GmailAPIError.invalidRequest }
    func deleteMessage(id: String) async throws { throw GmailAPIError.invalidRequest }
    func trashThread(id: String) async throws -> GmailThread { throw GmailAPIError.invalidRequest }
    func untrashThread(id: String) async throws -> GmailThread { throw GmailAPIError.invalidRequest }
    func deleteThread(id: String) async throws { throw GmailAPIError.invalidRequest }
    func batchModifyMessageLabels(messageIDs: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {
        throw GmailAPIError.invalidRequest
    }

    func createLabel(_ label: GmailLabelWrite) async throws -> GmailLabel { throw GmailAPIError.invalidRequest }
    func patchLabel(id: String, with label: GmailLabelWrite) async throws -> GmailLabel { throw GmailAPIError.invalidRequest }
    func deleteLabel(id: String) async throws { throw GmailAPIError.invalidRequest }
    func createDraft(rawMIME: String, threadID: String? = nil) async throws -> GmailDraft { throw GmailAPIError.invalidRequest }
    func updateDraft(id: String, rawMIME: String,
                     threadID: String? = nil) async throws -> GmailDraft { throw GmailAPIError.invalidRequest }
    func deleteDraft(id: String) async throws { throw GmailAPIError.invalidRequest }
    func sendDraft(id: String) async throws -> GmailMessage { throw GmailAPIError.invalidRequest }
    func sendMessage(rawMIME: String, threadID: String? = nil) async throws -> GmailMessage { throw GmailAPIError.invalidRequest }
    func listSendAs() async throws -> [GmailSendAs] { throw GmailAPIError.invalidRequest }
}

/// Typed Gmail REST operations layered over the generic authenticated transport.
public struct GmailAPIClient: GmailAPIClientProtocol, Sendable {
    /// RFC 5322 headers required to render a useful cached Gmail message.
    public static let requiredMetadataHeaders = [
        "From", "To", "Cc", "Bcc", "Reply-To", "Subject", "Date",
        "Message-ID", "In-Reply-To", "References", "Disposition-Notification-To",
        "Authentication-Results", "Content-Type"
    ]

    private let transport: GmailAPITransport
    private let userID: String

    /// Creates a client for `userID`; `me` addresses the authenticated mailbox.
    public init(transport: GmailAPITransport, userID: String = "me") {
        self.transport = transport
        self.userID = userID
    }

    /// Fetches the authenticated mailbox profile.
    public func getProfile() async throws -> GmailProfile {
        return try await transport.send(
            GmailAPIRequest(method: .get, path: "/users/\(Self.pathComponent(userID))/profile"),
            decoding: GmailProfile.self
        )
    }

    /// Lists the mailbox label catalog.
    public func listLabels() async throws -> [GmailLabel] {
        let response: GmailLabelListResponse = try await transport.send(
            GmailAPIRequest(method: .get, path: "/users/\(Self.pathComponent(userID))/labels"),
            decoding: GmailLabelListResponse.self
        )
        return response.labels
    }

    /// Fetches one label by immutable Gmail ID.
    public func getLabel(id: String) async throws -> GmailLabel {
        try validateID(id)
        return try await transport.send(
            GmailAPIRequest(
                method: .get,
                path: "/users/\(Self.pathComponent(userID))/labels/\(Self.pathComponent(id))"
            ),
            decoding: GmailLabel.self
        )
    }

    /// Lists message references, optionally filtered by labels or Gmail query.
    public func listMessages(
        maxResults: Int = 100,
        pageToken: String? = nil,
        labelIDs: [String] = [],
        query: String? = nil,
        includeSpamTrash: Bool = false
    ) async throws -> GmailMessagePage {
        var queryItems = [URLQueryItem(name: "maxResults", value: String(max(1, min(maxResults, 500))))]
        if let pageToken { queryItems.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        if let query { queryItems.append(URLQueryItem(name: "q", value: query)) }
        queryItems += labelIDs.map { URLQueryItem(name: "labelIds", value: $0) }
        if includeSpamTrash { queryItems.append(URLQueryItem(name: "includeSpamTrash", value: "true")) }
        return try await transport.send(
            GmailAPIRequest(
                method: .get,
                path: "/users/\(Self.pathComponent(userID))/messages",
                queryItems: queryItems
            ),
            decoding: GmailMessagePage.self
        )
    }

    /// Searches message references using Gmail's native search-box query syntax.
    public func searchMessages(
        _ query: String,
        maxResults: Int = 100,
        pageToken: String? = nil,
        labelIDs: [String] = [],
        includeSpamTrash: Bool = false
    ) async throws -> GmailMessagePage {
        try await listMessages(
            maxResults: maxResults,
            pageToken: pageToken,
            labelIDs: labelIDs,
            query: query,
            includeSpamTrash: includeSpamTrash
        )
    }

    /// Fetches one message detail response.
    public func getMessage(
        id: String,
        format: GmailMessageFormat = .metadata,
        metadataHeaders: [String] = []
    ) async throws -> GmailMessage {
        try validateID(id)
        var queryItems = [URLQueryItem(name: "format", value: format.rawValue)]
        queryItems += metadataHeaders.map { URLQueryItem(name: "metadataHeaders", value: $0) }
        return try await transport.send(
            GmailAPIRequest(
                method: .get,
                path: "/users/\(Self.pathComponent(userID))/messages/\(Self.pathComponent(id))",
                queryItems: queryItems
            ),
            decoding: GmailMessage.self
        )
    }

    /// Fetches one attachment body.
    public func getAttachment(messageID: String, attachmentID: String) async throws -> GmailAttachment {
        try validateID(messageID)
        try validateID(attachmentID)
        return try await transport.send(
            GmailAPIRequest(
                method: .get,
                path: "/users/\(Self.pathComponent(userID))/messages/\(Self.pathComponent(messageID))/attachments/\(Self.pathComponent(attachmentID))"
            ),
            decoding: GmailAttachment.self
        )
    }

    /// Lists chronological mailbox history after a cursor.
    public func listHistory(
        startHistoryID: String,
        maxResults: Int = 100,
        pageToken: String? = nil,
        labelID: String? = nil,
        historyTypes: [GmailHistoryType] = []
    ) async throws -> GmailHistoryPage {
        var queryItems = [
            URLQueryItem(name: "startHistoryId", value: startHistoryID),
            URLQueryItem(name: "maxResults", value: String(max(1, min(maxResults, 500))))
        ]
        if let pageToken { queryItems.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        if let labelID { queryItems.append(URLQueryItem(name: "labelId", value: labelID)) }
        queryItems += historyTypes.map { URLQueryItem(name: "historyTypes", value: $0.rawValue) }
        return try await transport.send(
            GmailAPIRequest(
                method: .get,
                path: "/users/\(Self.pathComponent(userID))/history",
                queryItems: queryItems
            ),
            decoding: GmailHistoryPage.self
        )
    }

    /// Adds and removes labels on one message.
    public func modifyMessageLabels(
        id: String,
        addLabelIDs: [String],
        removeLabelIDs: [String]
    ) async throws -> GmailMessage {
        try validateLabelMutation(id: id, add: addLabelIDs, remove: removeLabelIDs)
        return try await transport.send(
            GmailAPIRequest(
                method: .post,
                path: "/users/\(Self.pathComponent(userID))/messages/\(Self.pathComponent(id))/modify",
                body: Self.encode(GmailLabelMutation(addLabelIDs: addLabelIDs, removeLabelIDs: removeLabelIDs))
            ),
            decoding: GmailMessage.self
        )
    }

    /// Adds and removes labels on every message in one thread.
    public func modifyThreadLabels(
        id: String,
        addLabelIDs: [String],
        removeLabelIDs: [String]
    ) async throws -> GmailThread {
        try validateLabelMutation(id: id, add: addLabelIDs, remove: removeLabelIDs)
        return try await transport.send(
            GmailAPIRequest(
                method: .post,
                path: "/users/\(Self.pathComponent(userID))/threads/\(Self.pathComponent(id))/modify",
                body: Self.encode(GmailLabelMutation(addLabelIDs: addLabelIDs, removeLabelIDs: removeLabelIDs))
            ),
            decoding: GmailThread.self
        )
    }

    /// Moves one message to Trash.
    public func trashMessage(id: String) async throws -> GmailMessage {
        try await messageAction(id: id, action: "trash")
    }

    /// Restores one message from Trash.
    public func untrashMessage(id: String) async throws -> GmailMessage {
        try await messageAction(id: id, action: "untrash")
    }

    /// Permanently deletes one message.
    public func deleteMessage(id: String) async throws {
        try validateID(id)
        try await transport.send(GmailAPIRequest(
            method: .delete,
            path: "/users/\(Self.pathComponent(userID))/messages/\(Self.pathComponent(id))"
        ))
    }

    /// Moves one thread to Trash.
    public func trashThread(id: String) async throws -> GmailThread {
        try await threadAction(id: id, action: "trash")
    }

    /// Restores one thread from Trash.
    public func untrashThread(id: String) async throws -> GmailThread {
        try await threadAction(id: id, action: "untrash")
    }

    /// Permanently deletes one thread.
    public func deleteThread(id: String) async throws {
        try validateID(id)
        try await transport.send(GmailAPIRequest(
            method: .delete,
            path: "/users/\(Self.pathComponent(userID))/threads/\(Self.pathComponent(id))"
        ))
    }

    /// Applies label changes to up to 1,000 messages.
    public func batchModifyMessageLabels(
        messageIDs: [String],
        addLabelIDs: [String],
        removeLabelIDs: [String]
    ) async throws {
        guard !messageIDs.isEmpty, messageIDs.count <= 1000 else { throw GmailAPIError.invalidRequest }
        try messageIDs.forEach(validateID)
        try validateLabelMutation(id: "batch", add: addLabelIDs, remove: removeLabelIDs)
        try await transport.send(GmailAPIRequest(
            method: .post,
            path: "/users/\(Self.pathComponent(userID))/messages/batchModify",
            body: Self.encode(GmailBatchLabelMutation(
                ids: messageIDs,
                addLabelIDs: addLabelIDs,
                removeLabelIDs: removeLabelIDs
            ))
        ))
    }

    /// Creates a user label.
    public func createLabel(_ label: GmailLabelWrite) async throws -> GmailLabel {
        guard label.name?.isEmpty == false else { throw GmailAPIError.invalidRequest }
        return try await transport.send(
            GmailAPIRequest(
                method: .post,
                path: "/users/\(Self.pathComponent(userID))/labels",
                body: Self.encode(label)
            ),
            decoding: GmailLabel.self
        )
    }

    /// Patches a user label.
    public func patchLabel(id: String, with label: GmailLabelWrite) async throws -> GmailLabel {
        try validateID(id)
        return try await transport.send(
            GmailAPIRequest(
                method: .patch,
                path: "/users/\(Self.pathComponent(userID))/labels/\(Self.pathComponent(id))",
                body: Self.encode(label)
            ),
            decoding: GmailLabel.self
        )
    }

    /// Permanently deletes a user label.
    public func deleteLabel(id: String) async throws {
        try validateID(id)
        try await transport.send(GmailAPIRequest(
            method: .delete,
            path: "/users/\(Self.pathComponent(userID))/labels/\(Self.pathComponent(id))"
        ))
    }

    /// Creates a draft from RFC 2822 source.
    public func createDraft(rawMIME: String, threadID: String? = nil) async throws -> GmailDraft {
        try validateRawMIME(rawMIME)
        return try await transport.send(
            GmailAPIRequest(
                method: .post,
                path: "/users/\(Self.pathComponent(userID))/drafts",
                body: Self.encode(GmailDraftRequest(message: GmailRawMessage(rawMIME: rawMIME, threadID: threadID)))
            ),
            decoding: GmailDraft.self
        )
    }

    /// Replaces a draft's RFC 2822 source.
    public func updateDraft(id: String, rawMIME: String, threadID: String? = nil) async throws -> GmailDraft {
        try validateID(id)
        try validateRawMIME(rawMIME)
        return try await transport.send(
            GmailAPIRequest(
                method: .put,
                path: "/users/\(Self.pathComponent(userID))/drafts/\(Self.pathComponent(id))",
                body: Self.encode(GmailDraftRequest(message: GmailRawMessage(rawMIME: rawMIME, threadID: threadID)))
            ),
            decoding: GmailDraft.self
        )
    }

    /// Permanently deletes a draft.
    public func deleteDraft(id: String) async throws {
        try validateID(id)
        try await transport.send(GmailAPIRequest(
            method: .delete,
            path: "/users/\(Self.pathComponent(userID))/drafts/\(Self.pathComponent(id))"
        ))
    }

    /// Sends an existing draft.
    public func sendDraft(id: String) async throws -> GmailMessage {
        try validateID(id)
        return try await transport.send(
            GmailAPIRequest(
                method: .post,
                path: "/users/\(Self.pathComponent(userID))/drafts/send",
                body: Self.encode(GmailDraftSendRequest(id: id))
            ),
            decoding: GmailMessage.self
        )
    }

    /// Sends an RFC 2822 message and returns Gmail's created message.
    public func sendMessage(rawMIME: String, threadID: String? = nil) async throws -> GmailMessage {
        try validateRawMIME(rawMIME)
        return try await transport.send(
            GmailAPIRequest(
                method: .post,
                path: "/users/\(Self.pathComponent(userID))/messages/send",
                body: Self.encode(GmailRawMessage(rawMIME: rawMIME, threadID: threadID))
            ),
            decoding: GmailMessage.self
        )
    }

    /// Lists configured send-as identities and signature/default metadata.
    public func listSendAs() async throws -> [GmailSendAs] {
        let response: GmailSendAsListResponse = try await transport.send(
            GmailAPIRequest(method: .get, path: "/users/\(Self.pathComponent(userID))/settings/sendAs"),
            decoding: GmailSendAsListResponse.self
        )
        return response.sendAs
    }

    private func messageAction(id: String, action: String) async throws -> GmailMessage {
        try validateID(id)
        return try await transport.send(
            GmailAPIRequest(
                method: .post,
                path: "/users/\(Self.pathComponent(userID))/messages/\(Self.pathComponent(id))/\(action)"
            ),
            decoding: GmailMessage.self
        )
    }

    private func threadAction(id: String, action: String) async throws -> GmailThread {
        try validateID(id)
        return try await transport.send(
            GmailAPIRequest(
                method: .post,
                path: "/users/\(Self.pathComponent(userID))/threads/\(Self.pathComponent(id))/\(action)"
            ),
            decoding: GmailThread.self
        )
    }

    private func validateLabelMutation(id: String, add: [String], remove: [String]) throws {
        try validateID(id)
        guard add.count <= 100, remove.count <= 100 else { throw GmailAPIError.invalidRequest }
        try (add + remove).forEach(validateID)
    }

    private func validateID(_ id: String) throws {
        guard !id.isEmpty, id != ".", id != ".." else { throw GmailAPIError.invalidRequest }
    }

    private func validateRawMIME(_ rawMIME: String) throws {
        guard !rawMIME.isEmpty else { throw GmailAPIError.invalidRequest }
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        do { return try JSONEncoder().encode(value) }
        catch { throw GmailAPIError.invalidRequest }
    }

    private static func pathComponent(_ value: String) -> String {
        GmailAPIPathComponentEncoder.encode(value)
    }
}

private struct GmailLabelListResponse: Decodable {
    let labels: [GmailLabel]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        labels = try container.decodeIfPresent([GmailLabel].self, forKey: .labels) ?? []
    }

    private enum CodingKeys: String, CodingKey { case labels }
}

private struct GmailLabelMutation: Encodable {
    let addLabelIDs: [String]
    let removeLabelIDs: [String]

    private enum CodingKeys: String, CodingKey {
        case addLabelIDs = "addLabelIds"
        case removeLabelIDs = "removeLabelIds"
    }
}

private struct GmailBatchLabelMutation: Encodable {
    let ids: [String]
    let addLabelIDs: [String]
    let removeLabelIDs: [String]

    private enum CodingKeys: String, CodingKey {
        case ids
        case addLabelIDs = "addLabelIds"
        case removeLabelIDs = "removeLabelIds"
    }
}

private struct GmailDraftRequest: Encodable {
    let message: GmailRawMessage
}

private struct GmailDraftSendRequest: Encodable {
    let id: String
}

private struct GmailSendAsListResponse: Decodable {
    let sendAs: [GmailSendAs]

    private enum CodingKeys: String, CodingKey { case sendAs }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sendAs = try container.decodeIfPresent([GmailSendAs].self, forKey: .sendAs) ?? []
    }
}

public extension GmailAPIClient {
    /// Fetches one label by immutable Gmail ID.
    func label(id: String) async throws -> GmailLabel { try await getLabel(id: id) }

    /// Fetches one message detail response.
    func message(id: String, format: GmailMessageFormat = .metadata) async throws -> GmailMessage {
        try await getMessage(id: id, format: format)
    }

    /// Fetches one attachment body.
    func attachment(messageID: String, attachmentID: String) async throws -> GmailAttachment {
        try await getAttachment(messageID: messageID, attachmentID: attachmentID)
    }
}

extension GmailAPIClient: GmailAPITransporting {
    /// Returns the authenticated mailbox profile for the read backend.
    public func profile() async throws -> GmailProfile {
        try await getProfile()
    }

    /// Lists messages using the read backend's single-label projection.
    public func listMessages(
        labelID: String?,
        query: String?,
        pageToken: String?,
        maxResults: Int
    ) async throws -> GmailMessagePage {
        try await listMessages(
            maxResults: maxResults,
            pageToken: pageToken,
            labelIDs: labelID.map { [$0] } ?? [],
            query: query,
            includeSpamTrash: false
        )
    }

    /// Lists one label projection while preserving Gmail's spam/trash switch.
    public func listMessages(
        labelID: String?,
        query: String?,
        pageToken: String?,
        maxResults: Int,
        includeSpamTrash: Bool
    ) async throws -> GmailMessagePage {
        try await listMessages(
            maxResults: maxResults,
            pageToken: pageToken,
            labelIDs: labelID.map { [$0] } ?? [],
            query: query,
            includeSpamTrash: includeSpamTrash
        )
    }

    /// Loads one Gmail message in the requested representation.
    public func getMessage(
        messageID: String,
        format: GmailMessageFormat
    ) async throws -> GmailMessage {
        try await getMessage(id: messageID, format: format)
    }
}
