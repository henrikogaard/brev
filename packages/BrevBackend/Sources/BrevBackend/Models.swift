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

// MARK: - Account

/// User-visible identity for a connected mailbox.
///
/// Backend-agnostic: the same shape applies to IMAP/SMTP accounts and
/// any future standards or provider adapters.
public struct BrevAccount: Sendable, Hashable, Identifiable, Codable {
    public static let imapSMTPBackendIdentifier = "imap-smtp"
    public static let imapSMTPBackendDisplayName = "IMAP/SMTP"
    public static let gmailAPIBackendIdentifier = "gmail-api"
    public static let gmailAPIBackendDisplayName = "Gmail"

    public let id: String
    public let displayName: String
    public let emailAddress: String
    public let backendIdentifier: String
    public let backendDisplayName: String

    /// Canonical account id for an IMAP/SMTP account derived from its email
    /// address. Centralized so OAuth-token keying can't drift between
    /// provisioning and the app targets (a mismatch silently breaks refresh).
    public static func imapSMTPAccountID(forEmailAddress emailAddress: String) -> String {
        let normalized = emailAddress
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return "\(imapSMTPBackendIdentifier):\(normalized)"
    }

    /// Canonical account id for a Gmail API account derived from Google's
    /// stable token-bound OIDC subject. The subject is intentionally used
    /// instead of an email address because Workspace aliases can change.
    public static func gmailAPIAccountID(forGoogleSubject subject: String) -> String {
        let normalized = subject
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(gmailAPIBackendIdentifier):\(normalized)"
    }

    public init(
        id: String,
        displayName: String,
        emailAddress: String,
        backendIdentifier: String = BrevAccount.imapSMTPBackendIdentifier,
        backendDisplayName: String = BrevAccount.imapSMTPBackendDisplayName
    ) {
        self.id = id
        self.displayName = displayName
        self.emailAddress = emailAddress
        self.backendIdentifier = backendIdentifier
        self.backendDisplayName = backendDisplayName
    }

    public init(
        id: String,
        displayName: String,
        emailAddress: String
    ) {
        self.init(
            id: id,
            displayName: displayName,
            emailAddress: emailAddress,
            backendIdentifier: Self.imapSMTPBackendIdentifier,
            backendDisplayName: Self.imapSMTPBackendDisplayName
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case emailAddress
        case backendIdentifier
        case backendDisplayName
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        emailAddress = try container.decode(String.self, forKey: .emailAddress)
        // Accounts persisted before backend metadata was introduced now migrate
        // to the standards backend. Unsupported historical adapters are not
        // revived by decoding an old row.
        let decodedBackendIdentifier = try container.decodeNonEmptyStringIfPresent(
            forKey: .backendIdentifier
        )
        let decodedBackendDisplayName = try container.decodeNonEmptyStringIfPresent(
            forKey: .backendDisplayName
        )
        if let decodedBackendIdentifier {
            backendIdentifier = decodedBackendIdentifier
            backendDisplayName = decodedBackendDisplayName
                ?? Self.defaultDisplayName(forBackendIdentifier: decodedBackendIdentifier)
        } else {
            backendIdentifier = Self.imapSMTPBackendIdentifier
            backendDisplayName = Self.imapSMTPBackendDisplayName
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(emailAddress, forKey: .emailAddress)
        try container.encode(backendIdentifier, forKey: .backendIdentifier)
        try container.encode(backendDisplayName, forKey: .backendDisplayName)
    }

    private static func defaultDisplayName(forBackendIdentifier identifier: String) -> String {
        switch identifier {
        case gmailAPIBackendIdentifier:
            gmailAPIBackendDisplayName
        case imapSMTPBackendIdentifier:
            imapSMTPBackendDisplayName
        default:
            identifier
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeNonEmptyStringIfPresent(forKey key: Key) throws -> String? {
        guard let value = try decodeIfPresent(String.self, forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }
        return value
    }
}

// MARK: - Folder

/// Semantic role of a folder. Backends map their native folder kinds
/// onto these. `.custom` covers user-created folders.
public enum FolderRole: String, Sendable, Hashable, Codable, CaseIterable {
    case inbox
    case sent
    case drafts
    case trash
    case spam
    case archive
    case snoozed
    case scheduled
    case starred
    case allMail
    case custom
}

/// A mail folder. Always a plain Swift value type — view layer never
/// sees a persistence-backed `Folder` type (ADR-0028 invariant 5).
public struct Folder: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public let name: String
    public let role: FolderRole
    public let parentID: String?
    public let unreadCount: Int
    public let totalCount: Int

    public init(
        id: String,
        name: String,
        role: FolderRole,
        parentID: String? = nil,
        unreadCount: Int = 0,
        totalCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.parentID = parentID
        self.unreadCount = unreadCount
        self.totalCount = totalCount
    }
}

// MARK: - Correspondent

/// A single mail address with optional display name. Used for from /
/// to / cc / bcc lists.
public struct Correspondent: Sendable, Hashable, Codable {
    public let name: String?
    public let email: String

    public init(name: String? = nil, email: String) {
        self.name = name
        self.email = email
    }

    /// Human-friendly rendering. Falls back to the bare email when the
    /// display name is missing.
    public var displayName: String { name?.isEmpty == false ? name! : email }
}

// MARK: - Attachments

public struct Attachment: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public let name: String
    public let mimeType: String
    public let sizeBytes: Int
    public let isInline: Bool
    public let contentID: String?
    /// Backend-opaque hint used to fetch the attachment's bytes.
    /// Concrete backends embed whatever they need here (a URL path, a
    /// reference id, etc.) and parse it back in `downloadAttachment`.
    public let resource: String?

    public init(
        id: String,
        name: String,
        mimeType: String,
        sizeBytes: Int,
        isInline: Bool = false,
        contentID: String? = nil,
        resource: String? = nil
    ) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.isInline = isInline
        self.contentID = contentID
        self.resource = resource
    }
}

// MARK: - Flag color

/// A flag color in the Apple Mail-compatible palette.
///
/// Brev carries flag color as a provider-agnostic *semantic identity*,
/// never as a rendered color: the view/theme layer (`BrevDesign` /
/// `BrevThemes`) maps each case to a theme-aware swatch so the same
/// flag renders correctly under any theme. The backend layer imports no
/// UI (ADR-0028 invariant 1).
///
/// The raw value is Brev's own stable persistence key. It is
/// deliberately decoupled from the Apple `$MailFlagBit0..2` wire
/// encoding, whose ordinal-to-color mapping is reverse-engineered and
/// must be verified against a live Apple Mail mailbox by the future
/// IMAP/JMAP keyword encoder before it ships. See ADR-0019.
public enum FlagColor: Int, Sendable, Hashable, Codable, CaseIterable {
    case orange
    case red
    case purple
    case blue
    case yellow
    case green
    case gray
}

// MARK: - Message

/// List-level summary of a message. What the inbox list renders.
public struct MessageHeader: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public let threadID: String
    public let folderID: String
    public let from: Correspondent
    public let replyTo: [Correspondent]
    public let to: [Correspondent]
    public let cc: [Correspondent]
    public let bcc: [Correspondent]
    public let subject: String
    public let snippet: String
    public let date: Date
    public var isRead: Bool
    public var isFlagged: Bool
    public var isAnswered: Bool
    public var isForwarded: Bool
    public let hasAttachments: Bool
    /// The flag color, when one is assigned. A non-nil color implies the
    /// message is flagged. Providers that cannot persist color store it in
    /// Brev's local label store; see ADR-0019.
    public var flagColor: FlagColor?

    /// This message's own RFC 5322 Message-ID, when the provider reported one.
    /// Distinct from `threadID`, which names the conversation the message
    /// belongs to and may be an ancestor's Message-ID (ADR-0052).
    public let messageID: String?

    /// The Message-ID this message replies to, from RFC 5322 `In-Reply-To`.
    /// Threading is derived from this link; see ADR-0052.
    public let inReplyTo: String?

    /// Provider labels attached to the message, in server order. Populated
    /// only by backends advertising `BackendCapabilities.labels` (Gmail
    /// `X-GM-LABELS`); system labels keep their backslash prefix (`\Inbox`,
    /// `\Important`). Empty for folder-only providers.
    public var labels: [String]

    /// The message's RFC 5322 Message-ID when known, suitable for an outgoing
    /// reply's `In-Reply-To`/`References`.
    ///
    /// Prefers the explicit `messageID`. Headers cached before ADR-0052 have no
    /// `messageID`, and for those `threadID` still holds this message's own
    /// Message-ID — except when the message had none, where `threadID` fell back
    /// to the internal `folderID:uid` `id`, which is not a valid mail reference
    /// and is reported here as nil. Using `id` directly would emit
    /// `<folderID:uid>`, which no recipient can thread against.
    public var rfcMessageID: String? {
        if let messageID, !messageID.isEmpty { return messageID }
        return threadID == id ? nil : threadID
    }

    public init(
        id: String,
        threadID: String,
        folderID: String,
        from: Correspondent,
        replyTo: [Correspondent] = [],
        to: [Correspondent] = [],
        cc: [Correspondent] = [],
        bcc: [Correspondent] = [],
        subject: String,
        snippet: String,
        date: Date,
        isRead: Bool = false,
        isFlagged: Bool = false,
        isAnswered: Bool = false,
        isForwarded: Bool = false,
        hasAttachments: Bool = false,
        flagColor: FlagColor? = nil,
        messageID: String? = nil,
        inReplyTo: String? = nil,
        labels: [String] = []
    ) {
        self.id = id
        self.threadID = threadID
        self.messageID = messageID
        self.inReplyTo = inReplyTo
        self.labels = labels
        self.folderID = folderID
        self.from = from
        self.replyTo = replyTo
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.snippet = snippet
        self.date = date
        self.isRead = isRead
        self.isFlagged = isFlagged
        self.isAnswered = isAnswered
        self.isForwarded = isForwarded
        self.hasAttachments = hasAttachments
        self.flagColor = flagColor
    }

    enum CodingKeys: String, CodingKey {
        case id
        case threadID
        case messageID
        case inReplyTo
        case folderID
        case from
        case replyTo
        case to
        case cc
        case bcc
        case subject
        case snippet
        case date
        case isRead
        case isFlagged
        case isAnswered
        case isForwarded
        case hasAttachments
        case flagColor
        case labels
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        threadID = try container.decode(String.self, forKey: .threadID)
        messageID = try container.decodeIfPresent(String.self, forKey: .messageID)
        inReplyTo = try container.decodeIfPresent(String.self, forKey: .inReplyTo)
        folderID = try container.decode(String.self, forKey: .folderID)
        from = try container.decode(Correspondent.self, forKey: .from)
        replyTo = try container.decodeIfPresent([Correspondent].self, forKey: .replyTo) ?? []
        to = try container.decode([Correspondent].self, forKey: .to)
        cc = try container.decode([Correspondent].self, forKey: .cc)
        bcc = try container.decode([Correspondent].self, forKey: .bcc)
        subject = try container.decode(String.self, forKey: .subject)
        snippet = try container.decode(String.self, forKey: .snippet)
        date = try container.decode(Date.self, forKey: .date)
        isRead = try container.decode(Bool.self, forKey: .isRead)
        isFlagged = try container.decode(Bool.self, forKey: .isFlagged)
        isAnswered = try container.decode(Bool.self, forKey: .isAnswered)
        isForwarded = try container.decode(Bool.self, forKey: .isForwarded)
        hasAttachments = try container.decode(Bool.self, forKey: .hasAttachments)
        flagColor = try container.decodeIfPresent(FlagColor.self, forKey: .flagColor)
        labels = try container.decodeIfPresent([String].self, forKey: .labels) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(threadID, forKey: .threadID)
        try container.encodeIfPresent(messageID, forKey: .messageID)
        try container.encodeIfPresent(inReplyTo, forKey: .inReplyTo)
        try container.encode(folderID, forKey: .folderID)
        try container.encode(from, forKey: .from)
        try container.encode(replyTo, forKey: .replyTo)
        try container.encode(to, forKey: .to)
        try container.encode(cc, forKey: .cc)
        try container.encode(bcc, forKey: .bcc)
        try container.encode(subject, forKey: .subject)
        try container.encode(snippet, forKey: .snippet)
        try container.encode(date, forKey: .date)
        try container.encode(isRead, forKey: .isRead)
        try container.encode(isFlagged, forKey: .isFlagged)
        try container.encode(isAnswered, forKey: .isAnswered)
        try container.encode(isForwarded, forKey: .isForwarded)
        try container.encode(hasAttachments, forKey: .hasAttachments)
        try container.encodeIfPresent(flagColor, forKey: .flagColor)
        // Omit the key when empty so pre-labels cache snapshots stay byte-identical.
        if !labels.isEmpty {
            try container.encode(labels, forKey: .labels)
        }
    }

    /// Retains message metadata under a provider-confirmed identity after a move.
    public func withIdentity(_ restoredID: String, folderID restoredFolderID: String) -> MessageHeader {
        MessageHeader(
            id: restoredID, threadID: threadID == id ? restoredID : threadID, folderID: restoredFolderID,
            from: from, replyTo: replyTo, to: to, cc: cc, bcc: bcc, subject: subject, snippet: snippet, date: date,
            isRead: isRead, isFlagged: isFlagged, isAnswered: isAnswered, isForwarded: isForwarded,
            hasAttachments: hasAttachments, flagColor: flagColor, messageID: messageID, inReplyTo: inReplyTo, labels: labels
        )
    }

    /// A copy of this header filed under `threadID`. Used by
    /// `MessageThreadResolver` to name the conversation a message belongs to.
    public func withThreadID(_ threadID: String) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: threadID,
            folderID: folderID,
            from: from,
            replyTo: replyTo,
            to: to,
            cc: cc,
            bcc: bcc,
            subject: subject,
            snippet: snippet,
            date: date,
            isRead: isRead,
            isFlagged: isFlagged,
            isAnswered: isAnswered,
            isForwarded: isForwarded,
            hasAttachments: hasAttachments,
            flagColor: flagColor,
            messageID: messageID,
            inReplyTo: inReplyTo,
            labels: labels
        )
    }
}

/// Full message contents fetched on detail view.
public struct MessageBody: Sendable, Hashable, Codable {
    public let messageID: String
    public let html: String?
    public let plainText: String?
    public let attachments: [Attachment]
    public let listUnsubscribe: ListUnsubscribeOptions?
    /// Sender-requested read receipt target from `Disposition-Notification-To`,
    /// if the message asks for one. The reader must ask before sending.
    public let readReceiptRequest: ReadReceiptRequest?
    /// Received read receipt details from `message/disposition-notification`,
    /// if this message is itself a receipt.
    public let readReceiptNotification: ReadReceiptNotification?
    /// Raw value of the `Authentication-Results` header, if present.
    /// Used by `MessageHeaderAnalyzer` to surface DMARC/SPF/DKIM failures.
    public let authenticationResults: String?

    public init(
        messageID: String,
        html: String? = nil,
        plainText: String? = nil,
        attachments: [Attachment] = [],
        listUnsubscribe: ListUnsubscribeOptions? = nil,
        readReceiptRequest: ReadReceiptRequest? = nil,
        readReceiptNotification: ReadReceiptNotification? = nil,
        authenticationResults: String? = nil
    ) {
        self.messageID = messageID
        self.html = html
        self.plainText = plainText
        self.attachments = attachments
        self.listUnsubscribe = listUnsubscribe
        self.readReceiptRequest = readReceiptRequest
        self.readReceiptNotification = readReceiptNotification
        self.authenticationResults = authenticationResults
    }
}

// MARK: - Draft / send

public struct ReadReceiptRequest: Sendable, Hashable, Codable {
    public var notificationTo: String

    public init(notificationTo: String) {
        self.notificationTo = notificationTo
    }
}

public struct ReadReceiptResponse: Sendable, Hashable, Codable {
    public var finalRecipient: String
    public var originalMessageID: String?

    public init(finalRecipient: String, originalMessageID: String? = nil) {
        self.finalRecipient = finalRecipient
        self.originalMessageID = originalMessageID
    }
}

public struct ReadReceiptNotification: Sendable, Hashable, Codable {
    public var finalRecipient: String?
    public var originalMessageID: String?
    public var disposition: String

    public init(
        finalRecipient: String? = nil,
        originalMessageID: String? = nil,
        disposition: String
    ) {
        self.finalRecipient = finalRecipient
        self.originalMessageID = originalMessageID
        self.disposition = disposition
    }
}

public struct Draft: Sendable, Hashable, Identifiable, Codable {
    public let id: String // local UUID, stable across remote saves
    public var remoteID: String?
    public var identityID: String?
    /// Provider-neutral conversation identifier, when the source backend has
    /// a durable server-side thread identity (for example Gmail's thread ID).
    public var threadID: String?
    public var inReplyToMessageID: String?
    public var forwardedMessageID: String?
    public var to: [Correspondent]
    public var cc: [Correspondent]
    public var bcc: [Correspondent]
    public var subject: String
    public var htmlBody: String
    public var attachmentIDs: [String]
    public var scheduledFor: Date?
    public var readReceiptRequest: ReadReceiptRequest?
    public var readReceiptResponse: ReadReceiptResponse?
    /// Requested end-to-end security for this message (ADR-0021). Carried from
    /// compose to the backend so the send path can sign/encrypt before
    /// submission. `.none` for the vast majority of mail.
    public var securityMode: OutboundMessageSecurityMode

    public init(
        id: String,
        remoteID: String? = nil,
        identityID: String? = nil,
        threadID: String? = nil,
        inReplyToMessageID: String? = nil,
        forwardedMessageID: String? = nil,
        to: [Correspondent] = [],
        cc: [Correspondent] = [],
        bcc: [Correspondent] = [],
        subject: String = "",
        htmlBody: String = "",
        attachmentIDs: [String] = [],
        scheduledFor: Date? = nil,
        readReceiptRequest: ReadReceiptRequest? = nil,
        readReceiptResponse: ReadReceiptResponse? = nil,
        securityMode: OutboundMessageSecurityMode = .none
    ) {
        self.id = id
        self.remoteID = remoteID
        self.identityID = identityID
        self.threadID = threadID
        self.inReplyToMessageID = inReplyToMessageID
        self.forwardedMessageID = forwardedMessageID
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.htmlBody = htmlBody
        self.attachmentIDs = attachmentIDs
        self.scheduledFor = scheduledFor
        self.readReceiptRequest = readReceiptRequest
        self.readReceiptResponse = readReceiptResponse
        self.securityMode = securityMode
    }

    // Custom decoder so drafts persisted before `securityMode` existed still
    // decode (defaulting to `.none`) instead of failing with `keyNotFound`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        remoteID = try container.decodeIfPresent(String.self, forKey: .remoteID)
        identityID = try container.decodeIfPresent(String.self, forKey: .identityID)
        threadID = try container.decodeIfPresent(String.self, forKey: .threadID)
        inReplyToMessageID = try container.decodeIfPresent(String.self, forKey: .inReplyToMessageID)
        forwardedMessageID = try container.decodeIfPresent(String.self, forKey: .forwardedMessageID)
        to = try container.decodeIfPresent([Correspondent].self, forKey: .to) ?? []
        cc = try container.decodeIfPresent([Correspondent].self, forKey: .cc) ?? []
        bcc = try container.decodeIfPresent([Correspondent].self, forKey: .bcc) ?? []
        subject = try container.decodeIfPresent(String.self, forKey: .subject) ?? ""
        htmlBody = try container.decodeIfPresent(String.self, forKey: .htmlBody) ?? ""
        attachmentIDs = try container.decodeIfPresent([String].self, forKey: .attachmentIDs) ?? []
        scheduledFor = try container.decodeIfPresent(Date.self, forKey: .scheduledFor)
        readReceiptRequest = try container.decodeIfPresent(
            ReadReceiptRequest.self, forKey: .readReceiptRequest
        )
        readReceiptResponse = try container.decodeIfPresent(
            ReadReceiptResponse.self, forKey: .readReceiptResponse
        )
        securityMode = try container.decodeIfPresent(
            OutboundMessageSecurityMode.self, forKey: .securityMode
        ) ?? .none
    }
}

public enum SendResultWarning: String, Sendable, Hashable, Codable {
    case queuedForRetry
    case sentCopyAppendFailed
    case remoteDraftCleanupFailed
}

public struct SendResult: Sendable, Hashable, Codable {
    public let sentMessageID: String?
    public let scheduledFor: Date?
    public let warnings: [SendResultWarning]

    public init(
        sentMessageID: String? = nil,
        scheduledFor: Date? = nil,
        warnings: [SendResultWarning] = []
    ) {
        self.sentMessageID = sentMessageID
        self.scheduledFor = scheduledFor
        self.warnings = warnings
    }

    private enum CodingKeys: String, CodingKey {
        case sentMessageID
        case scheduledFor
        case warnings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sentMessageID = try container.decodeIfPresent(String.self, forKey: .sentMessageID)
        scheduledFor = try container.decodeIfPresent(Date.self, forKey: .scheduledFor)
        warnings = try container.decodeIfPresent([SendResultWarning].self, forKey: .warnings) ?? []
    }
}

// MARK: - Search

/// Backend-neutral search/filter query.
///
public enum SearchExecution: String, Sendable, Hashable, Codable {
    case cacheOnly
    case cacheThenServer
    case serverOnly
}

/// Backends that support only server-side text search (e.g.
/// `.serverSideSearch`) use `text` plus `folderID`; richer predicates
/// are a best-effort hint. Local-cache backends and fallback filtering
/// in `MessageSearchFallback` use all fields.
public struct SearchQuery: Sendable, Hashable, Codable {
    /// Free-text search across subject, body, and correspondents.
    public var text: String

    /// Restrict results to a specific folder. `nil` searches all folders.
    public var folderID: String?

    /// Filter by sender address or display name (partial match).
    public var from: String?

    /// Filter by any recipient address or name (partial match).
    public var to: String?

    /// Restrict results to messages whose date falls within the range.
    public var dateRange: ClosedRange<Date>?

    /// When `true`, only messages with attachments are returned.
    /// When `false`, only messages without. `nil` imposes no constraint.
    public var hasAttachments: Bool?

    /// When `true`, only unread messages are returned.
    /// When `false`, only read messages. `nil` imposes no constraint.
    public var isUnread: Bool?

    /// When `true`, only flagged/starred messages are returned.
    /// When `false`, only unflagged messages. `nil` imposes no constraint.
    public var isFlagged: Bool?

    /// Filter by subject line (partial, case-insensitive match).
    public var subject: String?

    /// Where the backend should search.
    ///
    /// `.cacheThenServer` preserves the historical provider-first behavior
    /// when no cache hit exists. Views can opt into `.cacheOnly` for fast,
    /// privacy-friendly local search and expose `.serverOnly` as an explicit
    /// user action.
    public var execution: SearchExecution

    public init(
        text: String = "",
        folderID: String? = nil,
        from: String? = nil,
        to: String? = nil,
        dateRange: ClosedRange<Date>? = nil,
        hasAttachments: Bool? = nil,
        isUnread: Bool? = nil,
        isFlagged: Bool? = nil,
        subject: String? = nil,
        execution: SearchExecution = .cacheThenServer
    ) {
        self.text = text
        self.folderID = folderID
        self.from = from
        self.to = to
        self.dateRange = dateRange
        self.hasAttachments = hasAttachments
        self.isUnread = isUnread
        self.isFlagged = isFlagged
        self.subject = subject
        self.execution = execution
    }

    public var hasSearchCriteria: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || folderID != nil
            || !(from?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || !(to?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || dateRange != nil
            || hasAttachments != nil
            || isUnread != nil
            || isFlagged != nil
            || !(subject?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    /// Returns `true` if the message header satisfies all non-nil predicates.
    ///
    /// Used by `MessageSearchFallback` (local filter for backends without
    /// server-side search) and the local SQLite/FTS search index.
    /// Text matching is case- and diacritic-insensitive.
    public func matches(_ header: MessageHeader) -> Bool {
        if let isUnread, header.isRead == isUnread { return false }
        if let isFlagged, header.isFlagged != isFlagged { return false }
        if let hasAttachments, header.hasAttachments != hasAttachments { return false }
        if let folderID, header.folderID != folderID { return false }
        if let dateRange, !dateRange.contains(header.date) { return false }
        if let from {
            let q = from.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchFrom = Self.normalizedContains(header.from.email, q)
                || Self.normalizedContains(header.from.name ?? "", q)
            if !matchFrom { return false }
        }
        if let to {
            let q = to.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchTo = header.to.contains {
                Self.normalizedContains($0.email, q)
                    || Self.normalizedContains($0.name ?? "", q)
            }
                || header.cc.contains {
                    Self.normalizedContains($0.email, q)
                        || Self.normalizedContains($0.name ?? "", q)
                }
                || header.bcc.contains {
                    Self.normalizedContains($0.email, q)
                        || Self.normalizedContains($0.name ?? "", q)
                }
            if !matchTo { return false }
        }
        if let subject {
            let q = subject.trimmingCharacters(in: .whitespacesAndNewlines)
            if !Self.normalizedContains(header.subject, q) { return false }
        }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedText.isEmpty {
            let matchText = Self.normalizedContains(header.subject, trimmedText)
                || Self.normalizedContains(header.snippet, trimmedText)
                || Self.normalizedContains(header.from.email, trimmedText)
                || Self.normalizedContains(header.from.name ?? "", trimmedText)
                || header.to.contains {
                    Self.normalizedContains($0.email, trimmedText)
                        || Self.normalizedContains($0.name ?? "", trimmedText)
                }
                || header.cc.contains {
                    Self.normalizedContains($0.email, trimmedText)
                        || Self.normalizedContains($0.name ?? "", trimmedText)
                }
                || header.bcc.contains {
                    Self.normalizedContains($0.email, trimmedText)
                        || Self.normalizedContains($0.name ?? "", trimmedText)
                }
            if !matchText { return false }
        }
        return true
    }

    private static func normalizedContains(_ value: String, _ query: String) -> Bool {
        let normalizedQuery = normalizedSearchString(query)
        guard !normalizedQuery.isEmpty else { return true }
        return normalizedSearchString(value).contains(normalizedQuery)
    }

    private static func normalizedSearchString(_ value: String) -> String {
        SearchTextNormalizer.normalized(value)
    }
}

// MARK: - Server aliases and signatures (ADR pending — read-only v1)

/// A server-side sender alias (additional From address) exposed by a provider.
///
/// Read-only in v1. Create/update/delete require an ADR review on conflict
/// and permission behavior before implementing. View code must never check
/// the concrete backend type to decide whether to show aliases.
public struct ServerAlias: Sendable, Hashable, Codable, Identifiable {
    /// Stable backend-assigned identifier.
    public let id: String
    /// The email address this alias sends as.
    public let email: String
    /// Optional display name for the alias.
    public let displayName: String?
    /// Whether this alias is the account default.
    public let isDefault: Bool

    public init(
        id: String,
        email: String,
        displayName: String? = nil,
        isDefault: Bool = false
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.isDefault = isDefault
    }
}

/// A server-managed signature or signature template.
///
/// Read-only in v1. The `isLocal` flag distinguishes a Brev-local
/// signature (stored in `SignatureSettings`) from one fetched from the
/// provider, preventing duplicate insertion in compose.
public struct ServerSignature: Sendable, Hashable, Codable, Identifiable {
    /// Stable backend-assigned identifier.
    public let id: String
    /// Human-readable name for display in pickers.
    public let name: String
    /// HTML or plain-text body content.
    public let body: String
    /// Whether this is the account-default signature on the server.
    public let isDefault: Bool

    public init(
        id: String,
        name: String,
        body: String,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.body = body
        self.isDefault = isDefault
    }
}

// MARK: - Calendar (ADR-0007)

public enum AttendeeState: String, Sendable, Hashable, Codable, CaseIterable {
    case accepted
    case tentative
    case declined
    case needsAction

    /// Human-readable label for display in the UI.
    public var displayLabel: String {
        switch self {
        case .accepted: "Accepted"
        case .tentative: "Tentative"
        case .declined: "Declined"
        case .needsAction: "Needs action"
        }
    }
}

public struct CalendarEvent: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let location: String?
    public let organizer: Correspondent?
    public let attendees: [Correspondent]
    public let description: String?

    public init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        location: String? = nil,
        organizer: Correspondent? = nil,
        attendees: [Correspondent] = [],
        description: String? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.organizer = organizer
        self.attendees = attendees
        self.description = description
    }
}

// MARK: - Events stream

/// Coarse change notification published by `MailBackend.subscribeToChanges`.
/// Folders/messages may be added, removed, or updated. The view layer
/// re-queries on receipt — payload is identifiers only, not deltas.
public enum MailEvent: Sendable, Hashable {
    case folderRefreshed(folderID: String)
    case messagesAdded(folderID: String, messageIDs: [String])
    case messagesRemoved(folderID: String, messageIDs: [String])
    case messagesUpdated(folderID: String, messageIDs: [String])
    case accountConnected(accountID: String)
    case accountDisconnected(accountID: String)
    case mailboxChanged(mailboxID: String)
    /// Progress of a multi-folder background refresh: `completed` of
    /// `total` folders synced. Emitted as the refresh loop advances so the
    /// view can show a determinate download indicator. `completed == total`
    /// (or `total == 0`) signals the pass is done and the indicator hides.
    /// Scoped to the emitting backend by the `from:` parameter of the
    /// change-stream consumer, like every other event here.
    case syncProgress(completed: Int, total: Int)
}

// MARK: - Mailbox

/// One inbox under a `BrevAccount`. Most users will have exactly
/// one; some accounts can have several (aliases / domains).
public struct Mailbox: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public let email: String
    public let displayName: String
    public let isPrimary: Bool

    public init(id: String, email: String, displayName: String, isPrimary: Bool = false) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.isPrimary = isPrimary
    }
}
