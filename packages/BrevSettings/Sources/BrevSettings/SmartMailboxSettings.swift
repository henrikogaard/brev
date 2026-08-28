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

public enum SmartMailboxKind: String, Codable, Equatable, Sendable {
    case messageSearch
    case attachmentSearch
}

public struct SmartMailbox: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var kind: SmartMailboxKind
    public var query: SavedQuery
    public var isEnabled: Bool

    public init(
        id: String,
        name: String,
        kind: SmartMailboxKind = .messageSearch,
        query: SavedQuery,
        isEnabled: Bool
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.query = query
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case query
        case isEnabled
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decodeIfPresent(SmartMailboxKind.self, forKey: .kind) ?? .messageSearch
        query = try container.decode(SavedQuery.self, forKey: .query)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
    }

    public struct SavedQuery: Codable, Equatable, Sendable {
        public var text: String
        public var from: String?
        public var to: String?
        public var hasAttachment: Bool?
        public var isUnread: Bool?
        public var isStarred: Bool?
        public var folderID: String?

        public init(
            text: String,
            from: String? = nil,
            to: String? = nil,
            hasAttachment: Bool? = nil,
            isUnread: Bool? = nil,
            isStarred: Bool? = nil,
            folderID: String? = nil
        ) {
            self.text = text
            self.from = from
            self.to = to
            self.hasAttachment = hasAttachment
            self.isUnread = isUnread
            self.isStarred = isStarred
            self.folderID = folderID
        }
    }
}

public struct SmartMailboxSettings: Codable, Equatable, Sendable {
    enum Key {
        static let mailboxes = "smartMailbox.mailboxes"
    }

    /// Stable `UserDefaults` key for the persisted mailboxes, exposed so
    /// `@AppStorage` bindings can observe changes without duplicating the literal.
    public static let storageKey = Key.mailboxes

    public var mailboxes: [SmartMailbox]
    /// Built-in Smart View identifiers the user has hidden. Persisting only
    /// disabled IDs keeps newly added built-ins enabled by default.
    public var disabledBuiltInIDs: Set<String>

    public static let defaults = SmartMailboxSettings(mailboxes: [])

    /// Creates persisted Smart View settings with built-ins enabled unless explicitly hidden.
    public init(mailboxes: [SmartMailbox], disabledBuiltInIDs: Set<String> = []) {
        self.mailboxes = mailboxes
        self.disabledBuiltInIDs = disabledBuiltInIDs
    }

    private enum CodingKeys: String, CodingKey {
        case mailboxes
        case disabledBuiltInIDs
    }

    /// Decodes current and legacy settings, defaulting absent built-in visibility to enabled.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mailboxes = try container.decodeIfPresent([SmartMailbox].self, forKey: .mailboxes) ?? []
        disabledBuiltInIDs = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .disabledBuiltInIDs
        ) ?? []
    }

    public static func load(from defaults: UserDefaults = .standard) -> SmartMailboxSettings {
        guard let data = defaults.data(forKey: Key.mailboxes),
              let settings = try? JSONDecoder().decode(SmartMailboxSettings.self, from: data) else {
            return .defaults
        }
        return settings
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Key.mailboxes)
    }

    public mutating func add(_ mailbox: SmartMailbox) {
        mailboxes.append(mailbox)
    }

    public mutating func remove(id: SmartMailbox.ID) {
        mailboxes.removeAll { $0.id == id }
    }

    public mutating func update(_ mailbox: SmartMailbox) {
        guard let index = mailboxes.firstIndex(where: { $0.id == mailbox.id }) else { return }
        mailboxes[index] = mailbox
    }

    /// Whether one built-in Smart View should appear in navigation.
    public func isBuiltInEnabled(_ id: String) -> Bool {
        !disabledBuiltInIDs.contains(id)
    }

    /// Shows or hides one built-in Smart View without affecting custom views.
    public mutating func setBuiltIn(_ id: String, isEnabled: Bool) {
        if isEnabled {
            disabledBuiltInIDs.remove(id)
        } else {
            disabledBuiltInIDs.insert(id)
        }
    }
}

struct SmartMailboxExecution: Equatable, Sendable {
    var mailboxID: SmartMailbox.ID
    var messageIDs: [MessageHeader.ID]
}

public extension SmartMailbox.SavedQuery {
    /// The persisted saved query as a backend `SearchQuery`, so a selected saved
    /// search can be executed against cached/loaded headers (ADR-0041).
    var searchQuery: SearchQuery {
        SearchQuery(
            text: text,
            folderID: folderID,
            from: from,
            to: to,
            hasAttachments: hasAttachment,
            isUnread: isUnread,
            isFlagged: isStarred
        )
    }
}

extension SmartMailboxSettings {
    /// Executes enabled smart mailboxes in persisted order and returns
    /// deterministic message id order for each mailbox.
    func execute(on headers: [MessageHeader]) -> [SmartMailboxExecution] {
        let orderedHeaders = headers.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.id < rhs.id
        }

        return mailboxes.compactMap { mailbox in
            guard mailbox.isEnabled else { return nil }
            guard mailbox.kind == .messageSearch else { return nil }
            let matchedIDs = orderedHeaders
                .filter { mailbox.query.searchQuery.matches($0) }
                .map(\.id)
            return SmartMailboxExecution(mailboxID: mailbox.id, messageIDs: matchedIDs)
        }
    }
}
