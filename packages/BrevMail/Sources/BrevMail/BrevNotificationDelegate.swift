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

/// `UNUserNotificationCenter` delegate wired by `BrevMailRootView` to
/// translate notification taps into backend operations.
///
/// The delegate exposes action closures that the view sets once at startup:
/// - `onOpen(route)`: invoked when the user taps the notification.
/// - `onMarkRead(route)`: invoked on the "Mark Read" action.
/// - `onArchive(route)`: invoked on the "Archive" action; the view is
///   responsible for resolving the archive folder and calling
///   `backend.move` on the correct account.
/// - `onReply(route, text)`: awaited for an inline notification reply so iOS
///   keeps the app alive until draft persistence and delivery finish.
///
/// Replies received during cold launch are buffered until the mail root has
/// restored accounts and installed `onReply`. The notification completion is
/// held with the buffered reply so iOS keeps the launch alive rather than
/// silently discarding the user's text.
public final class BrevNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    /// Async handler that stages and delivers a reply for its exact route.
    public typealias ReplyHandler = (NotificationMailRoute, String) async -> Void

    private struct PendingReply {
        let route: NotificationMailRoute
        let text: String
        let completionHandler: () -> Void
    }

    public var onOpen: ((NotificationMailRoute) -> Void)?
    public var onMarkRead: ((NotificationMailRoute) -> Void)?
    public var onArchive: ((NotificationMailRoute) -> Void)?
    public var onReply: ReplyHandler? {
        get {
            replyStateLock.lock()
            defer { replyStateLock.unlock() }
            return replyHandler
        }
        set {
            let pending: [PendingReply]
            replyStateLock.lock()
            replyHandler = newValue
            if newValue == nil {
                pending = []
            } else {
                pending = pendingReplies
                pendingReplies.removeAll()
            }
            replyStateLock.unlock()

            guard let newValue else { return }
            for reply in pending {
                deliver(reply, using: newValue)
            }
        }
    }

    private let replyStateLock = NSLock()
    private var replyHandler: ReplyHandler?
    private var pendingReplies: [PendingReply] = []

    var pendingReplyCount: Int {
        replyStateLock.lock()
        defer { replyStateLock.unlock() }
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
            onMarkRead?(route)
            completionHandler()
        case BrevLocalNotificationCenter.archiveActionIdentifier:
            onArchive?(route)
            completionHandler()
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
        replyStateLock.lock()
        if let handler = replyHandler {
            replyStateLock.unlock()
            deliver(pending, using: handler)
        } else {
            pendingReplies.append(pending)
            replyStateLock.unlock()
        }
    }

    private func deliver(_ reply: PendingReply, using handler: @escaping ReplyHandler) {
        Task {
            await handler(reply.route, reply.text)
            reply.completionHandler()
        }
    }
}
