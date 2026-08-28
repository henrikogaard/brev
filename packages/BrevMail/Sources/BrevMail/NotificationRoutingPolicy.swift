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

public struct NotificationMailRoute: Equatable, Sendable {
    public let accountID: String
    public let folderID: Folder.ID
    public let messageID: MessageHeader.ID
    public let sourceID: MailSourceID?

    public init(
        accountID: String,
        folderID: Folder.ID,
        messageID: MessageHeader.ID,
        sourceID: MailSourceID? = nil
    ) {
        self.accountID = accountID
        self.folderID = folderID
        self.messageID = messageID
        self.sourceID = sourceID
    }
}

enum NotificationNavigationDecision: Equatable, Sendable {
    case message(folderID: Folder.ID, messageID: MessageHeader.ID)
    case folder(folderID: Folder.ID)
    case unifiedInbox
}

enum NotificationAction: Equatable, Sendable {
    case markRead
    case archive
    case reply
    case snooze
}

enum NotificationActionDecision: Equatable, Sendable {
    case backgroundMutation
    case foregroundRoute
    case deferred(reason: String)
}

enum NotificationActionPolicy {
    static func decision(for action: NotificationAction) -> NotificationActionDecision {
        switch action {
        case .markRead, .archive, .reply:
            return .backgroundMutation
        case .snooze:
            return .deferred(reason: "Snooze needs a duration picker.")
        }
    }
}

public enum NotificationRoutingPolicy {
    static func userInfo(for route: NotificationMailRoute) -> [String: String] {
        userInfo(
            accountID: route.accountID,
            folderID: route.folderID,
            messageID: route.messageID,
            sourceID: route.sourceID
        )
    }

    static func userInfo(
        accountID: String,
        folderID: Folder.ID?,
        messageID: MessageHeader.ID,
        sourceID: MailSourceID?
    ) -> [String: String] {
        var userInfo = [
            "accountID": accountID,
            "messageID": messageID,
        ]
        if let folderID,
           !folderID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            userInfo["folderID"] = folderID
        }
        if let sourceID {
            userInfo["sourceAccountID"] = sourceID.accountID
            userInfo["sourceMailboxID"] = sourceID.mailboxID
        }
        return userInfo
    }

    public static func route(from url: URL) -> NotificationMailRoute? {
        guard url.scheme?.lowercased() == "brev",
              url.host == "message",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }
        let queryItems = components.queryItems ?? []
        let userInfo = queryItems.reduce(into: [AnyHashable: Any]()) { result, item in
            guard result[item.name] == nil,
                  let value = item.value
            else {
                return
            }
            result[item.name] = value
        }
        return route(from: userInfo)
    }

    static func route(from userInfo: [AnyHashable: Any]) -> NotificationMailRoute? {
        guard let accountID = stringValue(named: "accountID", in: userInfo),
              let folderID = stringValue(named: "folderID", in: userInfo),
              let messageID = stringValue(named: "messageID", in: userInfo)
        else {
            return nil
        }

        return NotificationMailRoute(
            accountID: accountID,
            folderID: folderID,
            messageID: messageID,
            sourceID: sourceID(from: userInfo)
        )
    }

    static func navigationDecision(
        for route: NotificationMailRoute,
        folders: [Folder],
        visibleHeaders: [MessageHeader]
    ) -> NotificationNavigationDecision {
        guard folders.contains(where: { $0.id == route.folderID }) else {
            return .unifiedInbox
        }

        guard visibleHeaders.contains(where: { $0.id == route.messageID && $0.folderID == route.folderID }) else {
            return .folder(folderID: route.folderID)
        }

        return .message(folderID: route.folderID, messageID: route.messageID)
    }

    private static func stringValue(named name: String, in userInfo: [AnyHashable: Any]) -> String? {
        let value = userInfo[name] as? String
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func sourceID(from userInfo: [AnyHashable: Any]) -> MailSourceID? {
        guard let accountID = stringValue(named: "sourceAccountID", in: userInfo),
              let mailboxID = stringValue(named: "sourceMailboxID", in: userInfo)
        else {
            return nil
        }
        return MailSourceID(accountID: accountID, mailboxID: mailboxID)
    }
}
