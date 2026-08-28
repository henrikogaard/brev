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

/// Distinguishes provider-defined system labels from user-created labels.
public enum ProviderLabelKind: String, Sendable, Hashable, Codable, CaseIterable {
    /// A provider-defined label such as Inbox or Starred.
    case system
    /// A label created by the mailbox owner or an administrator.
    case user
}

/// The visibility of a label in a provider's sidebar or mailbox list.
public enum ProviderLabelListVisibility: String, Sendable, Hashable, Codable, CaseIterable {
    /// Always show the label.
    case shown
    /// Show the label when it contains unread messages.
    case shownIfUnread
    /// Keep the label out of the sidebar.
    case hidden
}

/// The visibility of a label on individual message rows.
public enum ProviderLabelMessageVisibility: String, Sendable, Hashable, Codable, CaseIterable {
    /// Show the label on message rows when the provider supports it.
    case shown
    /// Keep the label off message rows while retaining the label itself.
    case hidden
}

/// Provider-neutral label visibility metadata for navigation and message rows.
public struct ProviderLabelVisibility: Sendable, Hashable, Codable {
    /// The label's sidebar/list visibility.
    public let sidebar: ProviderLabelListVisibility
    /// The label's message-row visibility.
    public let messageList: ProviderLabelMessageVisibility

    /// The conservative default for a newly discovered label.
    public static let `default` = ProviderLabelVisibility(
        sidebar: .shown,
        messageList: .shown
    )

    /// Creates label visibility metadata.
    public init(
        sidebar: ProviderLabelListVisibility = .shown,
        messageList: ProviderLabelMessageVisibility = .shown
    ) {
        self.sidebar = sidebar
        self.messageList = messageList
    }

    private enum CodingKeys: String, CodingKey {
        case sidebar
        case messageList
    }

    /// Decodes visibility metadata while defaulting fields added by later
    /// provider adapters.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sidebar = try container.decodeIfPresent(
            ProviderLabelListVisibility.self,
            forKey: .sidebar
        ) ?? .shown
        let messageList = try container.decodeIfPresent(
            ProviderLabelMessageVisibility.self,
            forKey: .messageList
        ) ?? .shown
        self.init(sidebar: sidebar, messageList: messageList)
    }
}

/// Optional foreground/background color metadata for a provider label.
public struct ProviderLabelColor: Sendable, Hashable, Codable {
    /// A provider-formatted foreground color, commonly a hex string.
    public let foregroundHex: String?
    /// A provider-formatted background color, commonly a hex string.
    public let backgroundHex: String?

    /// Creates optional label color metadata.
    public init(
        foregroundHex: String? = nil,
        backgroundHex: String? = nil
    ) {
        self.foregroundHex = foregroundHex
        self.backgroundHex = backgroundHex
    }
}

/// Optional message and thread counts reported by a provider label catalog.
public struct ProviderLabelCounts: Sendable, Hashable, Codable {
    /// Total messages carrying the label, when known.
    public let messagesTotal: Int?
    /// Unread messages carrying the label, when known.
    public let messagesUnread: Int?
    /// Total threads represented by the label, when known.
    public let threadsTotal: Int?
    /// Unread threads represented by the label, when known.
    public let threadsUnread: Int?

    /// Creates optional label counts.
    public init(
        messagesTotal: Int? = nil,
        messagesUnread: Int? = nil,
        threadsTotal: Int? = nil,
        threadsUnread: Int? = nil
    ) {
        self.messagesTotal = messagesTotal
        self.messagesUnread = messagesUnread
        self.threadsTotal = threadsTotal
        self.threadsUnread = threadsUnread
    }
}

/// An operation a provider may allow for one catalog label.
public enum ProviderLabelOperation: String, Sendable, Hashable, Codable, CaseIterable {
    /// Rename the label or one of its hierarchy components.
    case rename
    /// Delete the label from the provider.
    case delete
    /// Change sidebar or message-list visibility.
    case setVisibility
    /// Change the label's provider color.
    case setColor
    /// Add the label to messages.
    case applyToMessages
    /// Remove the label from messages.
    case removeFromMessages
}

/// A provider-neutral label catalog entry.
public struct ProviderLabel: Sendable, Hashable, Codable, Identifiable {
    /// Stable provider identifier for the label.
    public let id: String
    /// User-visible label name.
    public let name: String
    /// Stable parent identifier for nested labels, when supported.
    public let parentID: String?
    /// Whether the label is provider-defined or user-created.
    public let kind: ProviderLabelKind
    /// Sidebar and message-list visibility metadata.
    public let visibility: ProviderLabelVisibility
    /// Optional provider color metadata.
    public let color: ProviderLabelColor?
    /// Optional provider-reported counts.
    public let counts: ProviderLabelCounts?
    /// Operations the current account is allowed to perform on this label.
    public let allowedOperations: Set<ProviderLabelOperation>

    /// Creates a catalog entry and removes mutation actions that cannot apply
    /// to immutable system labels.
    public init(
        id: String,
        name: String,
        parentID: String? = nil,
        kind: ProviderLabelKind = .user,
        visibility: ProviderLabelVisibility = .default,
        color: ProviderLabelColor? = nil,
        counts: ProviderLabelCounts? = nil,
        allowedOperations: Set<ProviderLabelOperation>? = nil
    ) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.kind = kind
        self.visibility = visibility
        self.color = color
        self.counts = counts
        self.allowedOperations = Self.normalizedOperations(
            allowedOperations ?? Self.defaultOperations(for: kind),
            kind: kind
        )
    }

    /// Whether this entry is a provider-defined system label.
    public var isSystem: Bool { kind == .system }

    /// Whether the current account may rename this label.
    public var canRename: Bool { allowedOperations.contains(.rename) }

    /// Whether the current account may delete this label.
    public var canDelete: Bool { allowedOperations.contains(.delete) }

    /// Whether the current account may change label visibility.
    public var canSetVisibility: Bool { allowedOperations.contains(.setVisibility) }

    /// Whether the current account may change label color.
    public var canSetColor: Bool { allowedOperations.contains(.setColor) }

    /// Whether the current account may apply this label to messages.
    public var canApplyToMessages: Bool { allowedOperations.contains(.applyToMessages) }

    /// Whether the current account may remove this label from messages.
    public var canRemoveFromMessages: Bool { allowedOperations.contains(.removeFromMessages) }

    private static func defaultOperations(for kind: ProviderLabelKind) -> Set<ProviderLabelOperation> {
        switch kind {
        case .system:
            [.applyToMessages, .removeFromMessages]
        case .user:
            []
        }
    }

    private static func normalizedOperations(
        _ operations: Set<ProviderLabelOperation>,
        kind: ProviderLabelKind
    ) -> Set<ProviderLabelOperation> {
        guard kind == .system else { return operations }
        return operations.intersection([.applyToMessages, .removeFromMessages])
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case parentID
        case kind
        case visibility
        case color
        case counts
        case allowedOperations
    }

    /// Decodes a catalog entry while defaulting fields introduced after the
    /// initial label contract.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let parentID = try container.decodeIfPresent(String.self, forKey: .parentID)
        let kind = try container.decodeIfPresent(ProviderLabelKind.self, forKey: .kind) ?? .user
        let visibility = try container.decodeIfPresent(
            ProviderLabelVisibility.self,
            forKey: .visibility
        ) ?? .default
        let color = try container.decodeIfPresent(ProviderLabelColor.self, forKey: .color)
        let counts = try container.decodeIfPresent(ProviderLabelCounts.self, forKey: .counts)
        let allowedOperations = try container.decodeIfPresent(
            Set<ProviderLabelOperation>.self,
            forKey: .allowedOperations
        )
        self.init(
            id: id,
            name: name,
            parentID: parentID,
            kind: kind,
            visibility: visibility,
            color: color,
            counts: counts,
            allowedOperations: allowedOperations
        )
    }
}

/// Provides and manages a provider's label catalog.
public protocol ProviderLabelCatalogManaging: BackendExtensionService {
    /// Returns the current account-scoped label catalog.
    func labelCatalog(for sourceID: MailSourceID) async throws -> [ProviderLabel]

    /// Creates a user label under an optional parent label.
    func createLabel(
        name: String,
        parentID: String?,
        sourceID: MailSourceID
    ) async throws -> ProviderLabel

    /// Renames an existing user label.
    func renameLabel(
        id: String,
        name: String,
        sourceID: MailSourceID
    ) async throws -> ProviderLabel

    /// Deletes an existing user label.
    func deleteLabel(id: String, sourceID: MailSourceID) async throws

    /// Updates provider-supported visibility and color metadata.
    func updateLabel(
        id: String,
        visibility: ProviderLabelVisibility?,
        color: ProviderLabelColor?,
        sourceID: MailSourceID
    ) async throws -> ProviderLabel
}

/// One documented example of a provider's native search language.
public struct ServerSearchSyntaxExample: Sendable, Hashable, Codable, Identifiable {
    /// The provider-native query users can enter.
    public let query: String
    /// A short explanation suitable for a search-help surface.
    public let explanation: String

    /// Stable identity derived from the query text.
    public var id: String { query }

    /// Creates one search syntax example.
    public init(query: String, explanation: String) {
        self.query = query
        self.explanation = explanation
    }
}

/// Provider-neutral disclosure for a server's native search syntax.
public struct ServerSearchSyntaxDescription: Sendable, Hashable, Codable {
    /// Stable syntax identifier, opaque to the view layer.
    public let identifier: String
    /// User-visible name for the syntax.
    public let displayName: String
    /// Plain-language summary of what the syntax can search.
    public let summary: String
    /// Curated examples for search help and education.
    public let examples: [ServerSearchSyntaxExample]
    /// Optional provider documentation URL.
    public let documentationURL: URL?

    /// Creates a server-search syntax disclosure.
    public init(
        identifier: String,
        displayName: String,
        summary: String,
        examples: [ServerSearchSyntaxExample] = [],
        documentationURL: URL? = nil
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.summary = summary
        self.examples = examples
        self.documentationURL = documentationURL
    }
}

/// Describes the native query language exposed by a server-backed provider.
public protocol ServerSearchSyntaxProviding: BackendExtensionService {
    /// Returns the syntax disclosure for the requested account source.
    func serverSearchSyntax(for sourceID: MailSourceID) async throws -> ServerSearchSyntaxDescription?
}
