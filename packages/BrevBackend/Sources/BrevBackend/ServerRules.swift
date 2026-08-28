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

public struct ServerRule: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public var name: String
    public var isEnabled: Bool
    public var conditions: [ServerRuleCondition]
    public var actions: [ServerRuleAction]

    public init(
        id: String,
        name: String,
        isEnabled: Bool,
        conditions: [ServerRuleCondition],
        actions: [ServerRuleAction]
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.conditions = conditions
        self.actions = actions
    }

    public var requiresDestructiveConfirmation: Bool {
        actions.contains(where: \.isDestructive)
    }
}

public enum ServerRuleCondition: Sendable, Hashable, Codable {
    case senderContains(String)
    case recipientContains(String)
    case subjectContains(String)
    case hasAttachment
    case isUnread
    case providerPredicate(String)
}

public enum ServerRuleAction: Sendable, Hashable, Codable {
    case moveToFolder(id: String)
    case archive
    case markRead
    case markUnread
    case flag
    case delete
    case forward(to: String)
    case providerAction(String)

    public var isDestructive: Bool {
        switch self {
        case .delete, .forward:
            true
        case .moveToFolder, .archive, .markRead, .markUnread, .flag, .providerAction:
            false
        }
    }
}
