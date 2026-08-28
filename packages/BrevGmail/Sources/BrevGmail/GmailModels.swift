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

/// The mailbox-level profile returned by Gmail.
public struct GmailProfile: Codable, Sendable, Equatable {
    /// The authenticated mailbox address.
    public let emailAddress: String
    /// Total messages in the account, when returned by Gmail.
    public let messagesTotal: Int?
    /// Total threads in the account, when returned by Gmail.
    public let threadsTotal: Int?
    /// Cursor for the newest account history event.
    public let historyID: String?

    /// Creates a Gmail profile value.
    public init(emailAddress: String, messagesTotal: Int? = nil, threadsTotal: Int? = nil, historyID: String? = nil) {
        self.emailAddress = emailAddress
        self.messagesTotal = messagesTotal
        self.threadsTotal = threadsTotal
        self.historyID = historyID
    }

    private enum CodingKeys: String, CodingKey {
        case emailAddress
        case messagesTotal
        case threadsTotal
        case historyID = "historyId"
    }
}

/// A Gmail label and its account-wide counts/visibility metadata.
public struct GmailLabel: Codable, Sendable, Equatable, Identifiable {
    /// Stable Gmail label identifier.
    public let id: String
    /// Display name, including Gmail's nested-label path when applicable.
    public let name: String
    /// Gmail system or user label type.
    public let type: String?
    /// Sidebar visibility setting.
    public let labelListVisibility: String?
    /// Message-list visibility setting.
    public let messageListVisibility: String?
    /// Optional Gmail label color.
    public let color: GmailLabelColor?
    /// Message and thread counts, when returned.
    public let messagesTotal: Int?
    public let messagesUnread: Int?
    public let threadsTotal: Int?
    public let threadsUnread: Int?

    /// Creates a Gmail label value.
    public init(
        id: String,
        name: String,
        type: String? = nil,
        labelListVisibility: String? = nil,
        messageListVisibility: String? = nil,
        color: GmailLabelColor? = nil,
        messagesTotal: Int? = nil,
        messagesUnread: Int? = nil,
        threadsTotal: Int? = nil,
        threadsUnread: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.labelListVisibility = labelListVisibility
        self.messageListVisibility = messageListVisibility
        self.color = color
        self.messagesTotal = messagesTotal
        self.messagesUnread = messagesUnread
        self.threadsTotal = threadsTotal
        self.threadsUnread = threadsUnread
    }
}

/// Gmail's optional foreground/background label colors.
public struct GmailLabelColor: Codable, Sendable, Equatable {
    public let textColor: String?
    public let backgroundColor: String?

    /// Creates a label color value using Gmail's hex color strings.
    public init(textColor: String? = nil, backgroundColor: String? = nil) {
        self.textColor = textColor
        self.backgroundColor = backgroundColor
    }
}

/// A page of message references returned by Gmail list endpoints.
public struct GmailMessagePage: Codable, Sendable, Equatable {
    public let messages: [GmailMessageReference]
    public let nextPageToken: String?
    public let resultSizeEstimate: Int?

    /// Creates a message page.
    public init(messages: [GmailMessageReference] = [], nextPageToken: String? = nil, resultSizeEstimate: Int? = nil) {
        self.messages = messages
        self.nextPageToken = nextPageToken
        self.resultSizeEstimate = resultSizeEstimate
    }

    private enum CodingKeys: String, CodingKey {
        case messages
        case nextPageToken
        case resultSizeEstimate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messages = try container.decodeIfPresent([GmailMessageReference].self, forKey: .messages) ?? []
        nextPageToken = try container.decodeIfPresent(String.self, forKey: .nextPageToken)
        resultSizeEstimate = try container.decodeIfPresent(Int.self, forKey: .resultSizeEstimate)
    }
}

/// A lightweight Gmail message reference suitable for list and history calls.
public struct GmailMessageReference: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let threadID: String?

    /// Creates a Gmail message reference.
    public init(id: String, threadID: String? = nil) {
        self.id = id
        self.threadID = threadID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case threadID = "threadId"
    }
}

/// A Gmail message detail response. MIME payloads are intentionally modeled
/// only to the extent required by the next read-only provider slice.
public struct GmailMessage: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let threadID: String?
    public let labelIDs: [String]
    public let snippet: String?
    public let historyID: String?
    public let internalDate: String?
    public let sizeEstimate: Int?
    public let payload: GmailMessagePart?
    public let raw: String?

    /// Creates a Gmail message value.
    public init(
        id: String,
        threadID: String? = nil,
        labelIDs: [String] = [],
        snippet: String? = nil,
        historyID: String? = nil,
        internalDate: String? = nil,
        sizeEstimate: Int? = nil,
        payload: GmailMessagePart? = nil,
        raw: String? = nil
    ) {
        self.id = id
        self.threadID = threadID
        self.labelIDs = labelIDs
        self.snippet = snippet
        self.historyID = historyID
        self.internalDate = internalDate
        self.sizeEstimate = sizeEstimate
        self.payload = payload
        self.raw = raw
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case threadID = "threadId"
        case labelIDs = "labelIds"
        case snippet
        case historyID = "historyId"
        case internalDate
        case sizeEstimate
        case payload
        case raw
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        threadID = try container.decodeIfPresent(String.self, forKey: .threadID)
        labelIDs = try container.decodeIfPresent([String].self, forKey: .labelIDs) ?? []
        snippet = try container.decodeIfPresent(String.self, forKey: .snippet)
        historyID = try container.decodeIfPresent(String.self, forKey: .historyID)
        internalDate = try container.decodeIfPresent(String.self, forKey: .internalDate)
        sizeEstimate = try container.decodeIfPresent(Int.self, forKey: .sizeEstimate)
        payload = try container.decodeIfPresent(GmailMessagePart.self, forKey: .payload)
        raw = try container.decodeIfPresent(String.self, forKey: .raw)
    }
}

extension GmailMessage {
    /// Preserves richer cached content when a metadata refresh omits payloads.
    func preservingCachedContent(from existing: GmailMessage?) -> GmailMessage {
        guard let existing else { return self }
        return GmailMessage(
            id: id,
            threadID: threadID ?? existing.threadID,
            labelIDs: labelIDs,
            snippet: snippet ?? existing.snippet,
            historyID: historyID ?? existing.historyID,
            internalDate: internalDate ?? existing.internalDate,
            sizeEstimate: sizeEstimate ?? existing.sizeEstimate,
            payload: payload ?? existing.payload,
            raw: raw ?? existing.raw
        )
    }

    func withoutContent() -> GmailMessage {
        GmailMessage(
            id: id,
            threadID: threadID,
            labelIDs: labelIDs,
            snippet: snippet,
            historyID: historyID,
            internalDate: internalDate,
            sizeEstimate: sizeEstimate
        )
    }
}

/// A Gmail MIME part and its child parts.
public struct GmailMessagePart: Codable, Sendable, Equatable {
    public let partID: String?
    public let mimeType: String?
    public let filename: String?
    public let headers: [GmailMessageHeader]
    public let body: GmailMessageBody?
    public let parts: [GmailMessagePart]

    /// Creates a MIME part.
    public init(
        partID: String? = nil,
        mimeType: String? = nil,
        filename: String? = nil,
        headers: [GmailMessageHeader] = [],
        body: GmailMessageBody? = nil,
        parts: [GmailMessagePart] = []
    ) {
        self.partID = partID
        self.mimeType = mimeType
        self.filename = filename
        self.headers = headers
        self.body = body
        self.parts = parts
    }

    private enum CodingKeys: String, CodingKey {
        case partID = "partId"
        case mimeType
        case filename
        case headers
        case body
        case parts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        partID = try container.decodeIfPresent(String.self, forKey: .partID)
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        filename = try container.decodeIfPresent(String.self, forKey: .filename)
        headers = try container.decodeIfPresent([GmailMessageHeader].self, forKey: .headers) ?? []
        body = try container.decodeIfPresent(GmailMessageBody.self, forKey: .body)
        parts = try container.decodeIfPresent([GmailMessagePart].self, forKey: .parts) ?? []
    }
}

/// A MIME header from a Gmail message payload.
public struct GmailMessageHeader: Codable, Sendable, Equatable {
    public let name: String
    public let value: String

    /// Creates a MIME header.
    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// A Gmail MIME body, including base64url-encoded inline data when present.
public struct GmailMessageBody: Codable, Sendable, Equatable {
    public let size: Int?
    public let data: String?
    /// Provider attachment identifier used by `messages.attachments.get`.
    /// This is intentionally separate from Brev's stable attachment ID.
    public let attachmentID: String?

    /// Creates a MIME body descriptor.
    public init(size: Int? = nil, data: String? = nil, attachmentID: String? = nil) {
        self.size = size
        self.data = data
        self.attachmentID = attachmentID
    }

    private enum CodingKeys: String, CodingKey {
        case size
        case data
        case attachmentID = "attachmentId"
    }
}

/// Metadata for a Gmail attachment. Content is fetched separately using its
/// message and attachment IDs.
public struct GmailAttachment: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let messageID: String?
    public let filename: String?
    public let mimeType: String?
    public let size: Int?
    public let data: String?

    /// Creates an attachment descriptor.
    public init(
        id: String,
        messageID: String? = nil,
        filename: String? = nil,
        mimeType: String? = nil,
        size: Int? = nil,
        data: String? = nil
    ) {
        self.id = id
        self.messageID = messageID
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
        self.data = data
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case messageID = "messageId"
        case filename
        case mimeType
        case size
        case data
    }
}

/// A Gmail conversation returned by thread mutation or fetch operations.
public struct GmailThread: Codable, Sendable, Equatable, Identifiable {
    /// Immutable Gmail thread identifier.
    public let id: String
    /// Short thread preview, when supplied.
    public let snippet: String?
    /// History cursor for the thread, when supplied.
    public let historyID: String?
    /// Messages belonging to the thread.
    public let messages: [GmailMessage]

    /// Creates a Gmail thread value.
    public init(
        id: String,
        snippet: String? = nil,
        historyID: String? = nil,
        messages: [GmailMessage] = []
    ) {
        self.id = id
        self.snippet = snippet
        self.historyID = historyID
        self.messages = messages
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case snippet
        case historyID = "historyId"
        case messages
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        snippet = try container.decodeIfPresent(String.self, forKey: .snippet)
        historyID = try container.decodeIfPresent(String.self, forKey: .historyID)
        messages = try container.decodeIfPresent([GmailMessage].self, forKey: .messages) ?? []
    }
}

/// A Gmail draft resource containing an unsent message.
public struct GmailDraft: Codable, Sendable, Equatable, Identifiable {
    /// Immutable draft identifier.
    public let id: String
    /// Draft message metadata, when returned by Gmail.
    public let message: GmailMessage?

    /// Creates a Gmail draft value.
    public init(id: String, message: GmailMessage? = nil) {
        self.id = id
        self.message = message
    }
}

/// A raw MIME message request encoded for Gmail's API.
public struct GmailRawMessage: Codable, Sendable, Equatable {
    /// Base64url-encoded RFC 2822 message source.
    public let raw: String
    /// Optional existing thread to which Gmail should add the message.
    public let threadID: String?

    /// Encodes UTF-8 RFC 2822 source as unpadded base64url.
    public init(rawMIME: String, threadID: String? = nil) {
        raw = Self.base64URL(Data(rawMIME.utf8))
        self.threadID = threadID
    }

    /// Creates a request from an already base64url-encoded source.
    public init(rawBase64URL: String, threadID: String? = nil) {
        raw = rawBase64URL
        self.threadID = threadID
    }

    private enum CodingKeys: String, CodingKey {
        case raw
        case threadID = "threadId"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(raw, forKey: .raw)
        try container.encodeIfPresent(threadID, forKey: .threadID)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}

/// A patchable Gmail label request. Nil fields are omitted from JSON.
public struct GmailLabelWrite: Codable, Sendable, Equatable {
    /// Label display name.
    public let name: String?
    /// Visibility in Gmail's label list.
    public let labelListVisibility: String?
    /// Visibility in Gmail's message list.
    public let messageListVisibility: String?
    /// Optional user-label colors.
    public let color: GmailLabelColor?

    /// Creates a label create or patch payload.
    public init(
        name: String? = nil,
        labelListVisibility: String? = nil,
        messageListVisibility: String? = nil,
        color: GmailLabelColor? = nil
    ) {
        self.name = name
        self.labelListVisibility = labelListVisibility
        self.messageListVisibility = messageListVisibility
        self.color = color
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case labelListVisibility
        case messageListVisibility
        case color
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(labelListVisibility, forKey: .labelListVisibility)
        try container.encodeIfPresent(messageListVisibility, forKey: .messageListVisibility)
        try container.encodeIfPresent(color, forKey: .color)
    }
}

/// A Gmail send-as identity, including signature and default metadata.
public struct GmailSendAs: Codable, Sendable, Equatable, Identifiable {
    /// Send-as email address.
    public let sendAsEmail: String
    /// Optional display name.
    public let displayName: String?
    /// Optional reply-to address.
    public let replyToAddress: String?
    /// Gmail-sanitized HTML signature.
    public let signature: String?
    /// Whether this is the account's primary address.
    public let isPrimary: Bool?
    /// Whether this is the default From identity.
    public let isDefault: Bool?
    /// Whether Gmail treats the alias as the account owner.
    public let treatAsAlias: Bool?
    /// Gmail verification state for custom aliases.
    public let verificationStatus: String?

    /// Uses the send-as address as the stable identity.
    public var id: String { sendAsEmail }

    /// Creates a send-as identity.
    public init(
        sendAsEmail: String,
        displayName: String? = nil,
        replyToAddress: String? = nil,
        signature: String? = nil,
        isPrimary: Bool? = nil,
        isDefault: Bool? = nil,
        treatAsAlias: Bool? = nil,
        verificationStatus: String? = nil
    ) {
        self.sendAsEmail = sendAsEmail
        self.displayName = displayName
        self.replyToAddress = replyToAddress
        self.signature = signature
        self.isPrimary = isPrimary
        self.isDefault = isDefault
        self.treatAsAlias = treatAsAlias
        self.verificationStatus = verificationStatus
    }
}

/// A Gmail history page used for incremental synchronization.
public struct GmailHistoryPage: Codable, Sendable, Equatable {
    public let history: [GmailHistory]
    public let nextPageToken: String?
    public let historyID: String?

    /// Creates a history page.
    public init(history: [GmailHistory] = [], nextPageToken: String? = nil, historyID: String? = nil) {
        self.history = history
        self.nextPageToken = nextPageToken
        self.historyID = historyID
    }

    private enum CodingKeys: String, CodingKey {
        case history
        case nextPageToken
        case historyID = "historyId"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        history = try container.decodeIfPresent([GmailHistory].self, forKey: .history) ?? []
        nextPageToken = try container.decodeIfPresent(String.self, forKey: .nextPageToken)
        historyID = try container.decodeIfPresent(String.self, forKey: .historyID)
    }
}

/// One chronological Gmail history event and its message/label changes.
public struct GmailHistory: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let messages: [GmailMessageReference]
    public let messagesAdded: [GmailHistoryMessageChange]
    public let messagesDeleted: [GmailHistoryMessageChange]
    public let labelsAdded: [GmailHistoryLabelChange]
    public let labelsRemoved: [GmailHistoryLabelChange]

    /// Creates a history event.
    public init(
        id: String,
        messages: [GmailMessageReference] = [],
        messagesAdded: [GmailHistoryMessageChange] = [],
        messagesDeleted: [GmailHistoryMessageChange] = [],
        labelsAdded: [GmailHistoryLabelChange] = [],
        labelsRemoved: [GmailHistoryLabelChange] = []
    ) {
        self.id = id
        self.messages = messages
        self.messagesAdded = messagesAdded
        self.messagesDeleted = messagesDeleted
        self.labelsAdded = labelsAdded
        self.labelsRemoved = labelsRemoved
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case messages
        case messagesAdded
        case messagesDeleted
        case labelsAdded
        case labelsRemoved
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        messages = try container.decodeIfPresent([GmailMessageReference].self, forKey: .messages) ?? []
        messagesAdded = try container.decodeIfPresent([GmailHistoryMessageChange].self, forKey: .messagesAdded) ?? []
        messagesDeleted = try container.decodeIfPresent([GmailHistoryMessageChange].self, forKey: .messagesDeleted) ?? []
        labelsAdded = try container.decodeIfPresent([GmailHistoryLabelChange].self, forKey: .labelsAdded) ?? []
        labelsRemoved = try container.decodeIfPresent([GmailHistoryLabelChange].self, forKey: .labelsRemoved) ?? []
    }
}

/// A message added or deleted by a history event.
public struct GmailHistoryMessageChange: Codable, Sendable, Equatable {
    public let message: GmailMessageReference

    /// Creates a message change.
    public init(message: GmailMessageReference) {
        self.message = message
    }
}

/// A label addition or removal by a history event.
public struct GmailHistoryLabelChange: Codable, Sendable, Equatable {
    public let message: GmailMessageReference
    public let labelIDs: [String]

    /// Creates a label change.
    public init(message: GmailMessageReference, labelIDs: [String] = []) {
        self.message = message
        self.labelIDs = labelIDs
    }

    private enum CodingKeys: String, CodingKey {
        case message
        case labelIDs = "labelIds"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(GmailMessageReference.self, forKey: .message)
        labelIDs = try container.decodeIfPresent([String].self, forKey: .labelIDs) ?? []
    }
}
