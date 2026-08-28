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
import SwiftUI

/// Message actions a standalone (detached) message window can request. The
/// window has no navigation/command context of its own, so instead of mutating
/// state directly it posts a request that the main `BrevMailRootView` performs
/// through its normal command handlers (preserving undo, optimistic UI, and
/// folder refresh).
enum DetachedMessageCommand: String, Sendable {
    case reply
    case replyAll
    case forward
    case archive
    case delete
    case toggleFlag
    case move
    case setJunk

    /// Actions that remove the message from its folder, after which the
    /// standalone window should close.
    var dismissesWindow: Bool {
        switch self {
        case .archive, .delete, .move, .setJunk:
            return true
        case .reply, .replyAll, .forward, .toggleFlag:
            return false
        }
    }
}

/// The payload delivered with `Notification.Name.brevDetachedMessageCommand`.
struct DetachedMessageCommandRequest {
    let command: DetachedMessageCommand
    let header: MessageHeader
    let sourceID: MailSourceID?
}

extension Notification.Name {
    static let brevDetachedMessageCommand = Notification.Name("brev.detachedMessageCommand")
}

enum DetachedMessageCommandBus {
    static let requestKey = "request"

    @MainActor
    static func post(_ command: DetachedMessageCommand, header: MessageHeader, sourceID: MailSourceID?) {
        NotificationCenter.default.post(
            name: .brevDetachedMessageCommand,
            object: nil,
            userInfo: [
                requestKey: DetachedMessageCommandRequest(
                    command: command,
                    header: header,
                    sourceID: sourceID
                )
            ]
        )
    }
}

/// Receives detached-window command requests and forwards them to a handler.
/// Implemented as a `ViewModifier` so the main window's large body modifier
/// chain stays within the Swift type-checker's limits.
struct DetachedMessageCommandReceiver: ViewModifier {
    let handle: (DetachedMessageCommandRequest) -> Void

    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: .brevDetachedMessageCommand)
        ) { note in
            guard let request = note.userInfo?[DetachedMessageCommandBus.requestKey]
                as? DetachedMessageCommandRequest else { return }
            handle(request)
        }
    }
}
