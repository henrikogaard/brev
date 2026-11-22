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
import UserNotifications

/// `UNUserNotificationCenter` delegate wired by the app session and mail root
/// to translate notification taps and actions into backend operations (#307).
///
/// Actions received during cold launch are buffered until accounts restore and
/// handlers are installed. Each buffered action holds its system completion
/// handler so macOS/iOS keep the process alive until the mutation completes.
public final class BrevNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    /// Async handler for Mark-as-read and Archive notification actions.
    public typealias ActionHandler = @Sendable (NotificationMailRoute) async -> Void

    /// Async handler that stages and delivers a reply for its exact route.
    public typealias ReplyHandler = @Sendable (NotificationMailRoute, String) async -> Void

    private struct PendingAction {
        let route: NotificationMailRoute
        let completionHandler: () -> Void
    }

    private struct PendingReply {
        let route: NotificationMailRoute
        let text: String
        let completionHandler: () -> Void
    }

    public var onOpen: ((NotificationMailRoute) -> Void)?

    public var onMarkRead: ActionHandler? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return markReadHandler
        }
        set {
            let pending: [PendingAction]
            stateLock.lock()
            markReadHandler = newValue
            if newValue == nil {
                pending = []
            } else {
                pending = pendingMarkReads
                pendingMarkReads.removeAll()
            }
            stateLock.unlock()

            guard let newValue else { return }
            for action in pending {
                deliverAction(action, using: newValue)
            }
        }
    }

    public var onArchive: ActionHandler? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return archiveHandler
        }
        set {
            let pending: [PendingAction]
            stateLock.lock()
            archiveHandler = newValue
            if newValue == nil {
                pending = []
            } else {
                pending = pendingArchives
                pendingArchives.removeAll()
            }
            stateLock.unlock()

            guard let newValue else { return }
            for action in pending {
                deliverAction(action, using: newValue)
            }
        }
    }

    public var onReply: ReplyHandler? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return replyHandler
        }
        set {
            let pending: [PendingReply]
            stateLock.lock()
            replyHandler = newValue
            if newValue == nil {
                pending = []
            } else {
                pending = pendingReplies
                pendingReplies.removeAll()
            }
            stateLock.unlock()

            guard let newValue else { return }
            for reply in pending {
                deliverReply(reply, using: newValue)
            }
        }
    }

    private let stateLock = NSLock()
    private var markReadHandler: ActionHandler?
    private var archiveHandler: ActionHandler?
    private var replyHandler: ReplyHandler?
    private var pendingMarkReads: [PendingAction] = []
    private var pendingArchives: [PendingAction] = []
    private var pendingReplies: [PendingReply] = []

    var pendingMarkReadCount: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return pendingMarkReads.count
    }

    var pendingArchiveCount: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return pendingArchives.count
    }

    var pendingReplyCount: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return pendingReplies.count
    }

    override public init() {
        super.init()
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show the banner and play sound even when Brev is the frontmost
        // app — the user is checking mail, the toast is the affordance.
        completionHandler([.banner, .sound, .list])
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard let route = NotificationRoutingPolicy.route(
            from: response.notification.request.content.userInfo
        ) else {
            completionHandler()
            return
        }

        switch response.actionIdentifier {
        case BrevLocalNotificationCenter.markReadActionIdentifier:
            handleMarkRead(route: route, completionHandler: completionHandler)
        case BrevLocalNotificationCenter.archiveActionIdentifier:
            handleArchive(route: route, completionHandler: completionHandler)
        case BrevLocalNotificationCenter.replyActionIdentifier:
            guard let textResponse = response as? UNTextInputNotificationResponse else {
                completionHandler()
                return
            }
            handleReply(
                route: route,
                userText: textResponse.userText,
                completionHandler: completionHandler
            )
        default:
            onOpen?(route)
            completionHandler()
        }
    }

    func handleMarkRead(
        route: NotificationMailRoute,
        completionHandler: @escaping () -> Void
    ) {
        let pending = PendingAction(route: route, completionHandler: completionHandler)
        stateLock.lock()
        if let handler = markReadHandler {
            stateLock.unlock()
            deliverAction(pending, using: handler)
        } else {
            pendingMarkReads.append(pending)
            stateLock.unlock()
        }
    }

    func handleArchive(
        route: NotificationMailRoute,
        completionHandler: @escaping () -> Void
    ) {
        let pending = PendingAction(route: route, completionHandler: completionHandler)
        stateLock.lock()
        if let handler = archiveHandler {
            stateLock.unlock()
            deliverAction(pending, using: handler)
        } else {
            pendingArchives.append(pending)
            stateLock.unlock()
        }
    }

    func handleReply(
        route: NotificationMailRoute,
        userText: String,
        completionHandler: @escaping () -> Void
    ) {
        let text = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            completionHandler()
            return
        }

        let pending = PendingReply(
            route: route,
            text: text,
            completionHandler: completionHandler
        )
        stateLock.lock()
        if let handler = replyHandler {
            stateLock.unlock()
            deliverReply(pending, using: handler)
        } else {
            pendingReplies.append(pending)
            stateLock.unlock()
        }
    }

    private func deliverAction(_ action: PendingAction, using handler: @escaping ActionHandler) {
        Task {
            await handler(action.route)
            action.completionHandler()
        }
    }

    private func deliverReply(_ reply: PendingReply, using handler: @escaping ReplyHandler) {
        Task {
            await handler(reply.route, reply.text)
            reply.completionHandler()
        }
    }
}
