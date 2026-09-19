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
    case toggleRead
    case toggleFlag
    case toggleSnooze
    case toggleDone
    case move
    case copyToFolder
    case copyToLocalFolder
    case moveToLocalFolder
    case setJunk
    case blockSender
    case saveAs
    case createTask
    case createRule
    case createMeeting
    case addNote
    case followUp
    case downloadOffline
    case properties
    case showHeaders
    case viewSource
    case openInNewWindow

    /// Actions that remove the message from its folder, after which the
    /// standalone window should close.
    var dismissesWindow: Bool {
        switch self {
        case .archive, .delete, .move, .moveToLocalFolder, .setJunk, .blockSender:
            return true
        case .reply, .replyAll, .forward, .toggleRead, .toggleFlag, .toggleSnooze,
             .toggleDone, .copyToFolder, .copyToLocalFolder, .saveAs, .createTask,
             .createRule, .createMeeting, .addNote, .followUp, .downloadOffline,
             .properties, .showHeaders, .viewSource, .openInNewWindow:
            return false
        }
    }

    /// Maps a consolidated reader-menu action (`MessageCommandPresentation.
    /// readerMenu`) onto its command-bus equivalent. Returns nil for actions
    /// that are performed locally by the presenting view (Print/PDF need the
    /// loaded body) or that are row-only (Select, Pin to Top).
    init?(menuAction: MessageContextMenuAction) {
        switch menuAction {
        case .openInNewWindow: self = .openInNewWindow
        case .toggleRead: self = .toggleRead
        case .toggleFlag: self = .toggleFlag
        case .toggleSnooze: self = .toggleSnooze
        case .toggleDone: self = .toggleDone
        case .reply: self = .reply
        case .replyAll: self = .replyAll
        case .forward: self = .forward
        case .archive: self = .archive
        case .move: self = .move
        case .copyToFolder: self = .copyToFolder
        case .copyToLocalFolder: self = .copyToLocalFolder
        case .moveToLocalFolder: self = .moveToLocalFolder
        case .setJunk: self = .setJunk
        case .blockSender: self = .blockSender
        case .delete: self = .delete
        case .saveAs: self = .saveAs
        case .createTask: self = .createTask
        case .createRule: self = .createRule
        case .createMeeting: self = .createMeeting
        case .addNote: self = .addNote
        case .followUp: self = .followUp
        case .downloadOffline: self = .downloadOffline
        case .properties: self = .properties
        case .showHeaders: self = .showHeaders
        case .viewSource: self = .viewSource
        case .select, .pinToTop, .print, .exportPDF:
            return nil
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
