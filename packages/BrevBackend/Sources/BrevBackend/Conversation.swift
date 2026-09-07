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

/// An actual message location, independent of a list's currently selected folder.
public struct ConversationLocation: Hashable, Codable, Sendable {
    public let sourceID: MailSourceID
    public let folderID: Folder.ID
    public let messageID: MessageHeader.ID
    /// Provider folder generation when identity depends on it, such as IMAP UIDVALIDITY.
    public let folderGeneration: UInt64?

    /// Creates a source-owned location; providers validate its generation before remote access.
    public init(sourceID: MailSourceID, folderID: Folder.ID, messageID: MessageHeader.ID, folderGeneration: UInt64? = nil) {
        self.sourceID = sourceID
        self.folderID = folderID
        self.messageID = messageID
        self.folderGeneration = folderGeneration
    }
}

/// A conversation member retains its own folder and optional reply-header metadata.
public struct ConversationMember: Hashable, Sendable, Identifiable {
    public let sourceID: MailSourceID
    public let header: MessageHeader
    public let folderGeneration: UInt64?
    /// Nil means References was not fetched; an empty array means known absent.
    public let references: [String]?
    public var location: ConversationLocation {
        ConversationLocation(
            sourceID: sourceID,
            folderID: header.folderID,
            messageID: header.id,
            folderGeneration: folderGeneration
        )
    }

    public var id: ConversationLocation { location }

    /// Creates a member without changing its provider message or thread identity.
    public init(sourceID: MailSourceID, header: MessageHeader, folderGeneration: UInt64? = nil, references: [String]? = nil) {
        self.sourceID = sourceID
        self.header = header
        self.folderGeneration = folderGeneration
        self.references = references
    }
}

/// Coverage of the requested source/folder scope; cached never implies server completeness.
public enum ConversationCoverage: String, Sendable {
    case cached, loading, partial, completeForScope
}

/// Validated source-owned members and coverage around one stable selected message.
public struct ConversationSnapshot: Sendable {
    public let anchor: ConversationLocation
    public let members: [ConversationMember]
    public let coverage: ConversationCoverage
    public let excludedFolderIDs: [Folder.ID]
    public let unavailableFolderIDs: [Folder.ID]
    public let ambiguousIdentifiers: [String]
    public let continuation: String?

    /// Validates source isolation, unique locations, anchor retention and honest completion.
    public init(anchor: ConversationLocation, members: [ConversationMember], coverage: ConversationCoverage,
                excludedFolderIDs: [Folder.ID] = [], unavailableFolderIDs: [Folder.ID] = [],
                ambiguousIdentifiers: [String] = [], continuation: String? = nil) throws {
        guard members.allSatisfy({ $0.sourceID == anchor.sourceID }) else { throw ConversationLookupError.foreignSource }
        guard members.contains(where: { $0.location == anchor }), Set(members.map(\.location)).count == members.count else {
            throw ConversationLookupError.invalidSnapshot
        }
        var generations: [Folder.ID: Set<UInt64>] = [:]
        for member in members {
            if let value = member.folderGeneration { generations[member.header.folderID, default: []].insert(value) }
        }
        guard generations.values.allSatisfy({ $0.count <= 1 }) else { throw ConversationLookupError.invalidSnapshot }
        guard coverage != .completeForScope ||
            (unavailableFolderIDs.isEmpty && ambiguousIdentifiers.isEmpty && continuation == nil) else {
            throw ConversationLookupError.invalidSnapshot
        }
        self.anchor = anchor
        self.members = members.sorted {
            if $0.header.date != $1.header.date { return $0.header.date < $1.header.date }
            if $0.header.folderID != $1.header.folderID { return $0.header.folderID < $1.header.folderID }
            return $0.header.id < $1.header.id
        }
        self.coverage = coverage
        self.excludedFolderIDs = Array(Set(excludedFolderIDs)).sorted()
        self.unavailableFolderIDs = Array(Set(unavailableFolderIDs)).sorted()
        self.ambiguousIdentifiers = Array(Set(ambiguousIdentifiers)).sorted()
        self.continuation = continuation
    }
}

/// Read-only conversation lookup within existing local metadata, with no network calls.
/// Callers gate this service on `.cachedConversations` in extended capabilities.
public protocol CachedConversationProviding: BackendExtensionService {
    /// Returns cached related members, retaining the selected anchor when it is not persisted.
    func cachedConversation(around anchor: ConversationMember, includeSpamAndTrash: Bool) async throws -> ConversationSnapshot
}

/// Optional remote discovery, invoked only after the account's explicit related-mail consent.
public protocol RelatedConversationLoading: CachedConversationProviding {
    /// Loads related headers within the anchor source; bodies and attachments remain lazy.
    func loadRelatedConversation(around anchor: ConversationMember, includeSpamAndTrash: Bool, continuation: String?,
                                 onUpdate: @escaping @Sendable (ConversationSnapshot) async -> Void) async throws
        -> ConversationSnapshot
}

/// Safe errors for invalid conversation state, source or reply metadata.
public enum ConversationLookupError: Error, LocalizedError, Sendable {
    case foreignSource, invalidSnapshot, invalidMetadata
    public var errorDescription: String? {
        switch self {
        case .foreignSource: String(localized: "Related messages belong to a different mailbox.", bundle: .module)
        case .invalidSnapshot: String(localized: "The conversation changed. Load related messages again.", bundle: .module)
        case .invalidMetadata: String(localized: "Some reply headers could not be interpreted safely.", bundle: .module)
        }
    }
}
