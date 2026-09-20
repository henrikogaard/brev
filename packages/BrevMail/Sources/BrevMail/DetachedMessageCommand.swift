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

/// Reader actions performed by a single owning mail root, preserving undo,
/// optimistic UI, and folder refresh without process-wide broadcasts.
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

    /// These commands resolve destinations or roles from the loaded folder catalog.
    var requiresFolderList: Bool {
        switch self {
        case .archive, .delete, .setJunk, .move, .copyToFolder: true
        default: false
        }
    }

    /// Root mutation responses are scoped to the selected source and folder.
    var activatesMutationFolder: Bool {
        switch self {
        case .archive, .delete, .setJunk, .toggleRead, .toggleFlag, .blockSender: true
        default: false
        }
    }

    /// Return mutations and presentations to the owning mailbox window.
    /// Detached readers capture an immutable header, so stateful toggles must
    /// leave that snapshot instead of allowing a second stale-header action.
    var dismissesWindow: Bool {
        switch self {
        case .downloadOffline:
            return false
        case .reply, .replyAll, .forward, .archive, .delete, .move,
             .copyToFolder, .copyToLocalFolder, .moveToLocalFolder, .setJunk,
             .blockSender, .saveAs, .createTask, .createRule, .createMeeting,
             .addNote, .followUp, .properties, .showHeaders, .viewSource,
             .openInNewWindow, .toggleSnooze, .toggleRead, .toggleFlag, .toggleDone:
            return true
        }
    }

    /// Maps a consolidated reader-menu action (`MessageCommandPresentation.
    /// readerMenu`) onto its owned-command equivalent. Returns nil for actions
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

/// A reader action and its source-owned target, retained only in memory.
struct DetachedMessageCommandRequest {
    let command: DetachedMessageCommand
    let header: MessageHeader
    let sourceID: MailSourceID?
}

/// The enclosing reader/window provides exactly one command owner.
private struct ReaderCommandActionKey: EnvironmentKey {
    static let defaultValue: (@MainActor (DetachedMessageCommandRequest) -> Void)? = nil
}

extension EnvironmentValues {
    var readerCommandAction: (@MainActor (DetachedMessageCommandRequest) -> Void)? {
        get { self[ReaderCommandActionKey.self] }
        set { self[ReaderCommandActionKey.self] = newValue }
    }
}

/// Opaque scene identity for a one-shot reader action handoff. Mail content is
/// kept in memory and is never serialized into scene restoration data.
public struct ReaderCommandWindowPayload: Codable, Hashable, Sendable {
    let id: UUID
}

@MainActor
enum ReaderCommandHandoff {
    private static var pending: [UUID: DetachedMessageCommandRequest] = [:]

    static func enqueue(_ request: DetachedMessageCommandRequest) -> ReaderCommandWindowPayload {
        let payload = ReaderCommandWindowPayload(id: UUID())
        pending[payload.id] = request
        // If scene creation is abandoned, do not retain mail content for the
        // remainder of the app session. This does not schedule or retry actions.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(300))
            pending.removeValue(forKey: payload.id)
        }
        return payload
    }

    static func take(_ payload: ReaderCommandWindowPayload) -> DetachedMessageCommandRequest? {
        pending.removeValue(forKey: payload.id)
    }

    static func peek(_ payload: ReaderCommandWindowPayload) -> DetachedMessageCommandRequest? {
        pending[payload.id]
    }
}

/// Applies a reader's source context before its owner can dispatch a mutation.
@MainActor
enum ReaderCommandSourceHandoff {
    static func prepare(
        _ request: DetachedMessageCommandRequest,
        navigation: MailNavigationState,
        sections: [MailSourceSection],
        applySection: (MailSourceSection) -> Void
    ) -> Bool {
        if let sourceID = request.sourceID ?? navigation.selectedSourceID {
            guard let section = sections.first(where: { $0.id == sourceID }) else { return false }
            if request.command.requiresFolderList, section.loadError != nil { return false }
            let activatesFolder = request.command.activatesMutationFolder
                || (request.command.requiresFolderList && navigation.selectedSourceID != sourceID)
            if activatesFolder,
               navigation.selectedSourceID != sourceID || navigation.selectedFolderID != request.header.folderID {
                navigation.selectFolder(request.header.folderID, in: sourceID)
            }
            if request.command.requiresFolderList || request.command.activatesMutationFolder,
               section.loadError == nil {
                applySection(section)
            }
        }
        return true
    }
}
