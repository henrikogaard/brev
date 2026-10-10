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

/// What the pushed iPhone reader does once the message it shows has left the open folder.
enum CompactReaderRemovalOutcome: Equatable, Sendable {
    /// The shown message is unaffected.
    case stay
    /// Keep the reader open on this message (the survivor that inherited selection).
    case show(MessageHeader.ID)
    /// Pop the reader back to the message list.
    case returnToList
}

/// How the reader responds after archive, delete or move of the message it shows.
enum CompactReaderAfterRemovalBehavior: Sendable {
    /// iOS Mail default: advance to the neighbouring message, or pop when none is left.
    case showNext
    /// Always pop back to the list.
    case returnToList
}

/// The "after archive" policy for the pushed reader.
enum CompactReaderRemovalPolicy {
    /// Decides the reader's next state after headers were removed from the open folder.
    /// - Parameters:
    ///   - shownMessageID: The message currently open in the reader.
    ///   - removedMessageIDs: Messages that just left the folder.
    ///   - selectionAfterRemoval: The selection `MailNavigationState` settled on once the removal applied.
    ///   - behavior: Whether to advance to the next message or return to the list.
    static func outcome(
        shownMessageID: MessageHeader.ID,
        removedMessageIDs: Set<MessageHeader.ID>,
        selectionAfterRemoval: MessageHeader.ID?,
        behavior: CompactReaderAfterRemovalBehavior = .showNext
    ) -> CompactReaderRemovalOutcome {
        guard removedMessageIDs.contains(shownMessageID) else { return .stay }
        switch behavior {
        case .returnToList:
            return .returnToList
        case .showNext:
            guard let selectionAfterRemoval, !removedMessageIDs.contains(selectionAfterRemoval) else {
                return .returnToList
            }
            return .show(selectionAfterRemoval)
        }
    }
}

/// One item of the pushed reader's navigation bar.
enum CompactReaderNavigationBarAction: Equatable, Sendable {
    case previousMessage
    case nextMessage
    /// The single ••• menu.
    case overflow
}

/// One item of the pushed reader's bottom bar.
enum CompactReaderBottomBarAction: Hashable, Sendable {
    case archive
    case trash
    case move
    case replyMenu
    case compose
    /// Never part of the bottom bar; present so tests can prove the menu is not duplicated there.
    case overflow
}

/// An entry of the reply menu in the bottom bar.
enum CompactReaderReplyMenuAction: Hashable, Sendable {
    case reply
    case replyAll
    case forward
}

/// A block of the single ••• menu.
enum CompactReaderOverflowSection: Hashable, Sendable {
    /// Related-mail actions from the related-conversation controller.
    case relatedMail
    /// The Original / dark-mode body toggle.
    case renderingToggle
    /// The shared, capability-gated message inventory (`MessageCommandPresentation.readerMenu`).
    case messageActions
    /// Hands the message to the AI mailbox chat.
    case askAI
}

/// The inventory of the pushed reader's chrome, mirroring iOS Mail.
enum CompactReaderChromePolicy {
    /// Previous and next message chevrons, then the one overflow menu.
    static let navigationBarActions: [CompactReaderNavigationBarAction] = [
        .previousMessage, .nextMessage, .overflow
    ]

    /// Reply, Reply All and Forward behind the bottom bar's reply button.
    static let replyMenuActions: [CompactReaderReplyMenuAction] = [.reply, .replyAll, .forward]

    /// Archive when the account has an archive folder, otherwise Delete (the existing
    /// swipe-action preference), then Move, the reply menu and Compose.
    static func bottomBarActions(
        hasArchiveFolder: Bool,
        hasMoveTargets: Bool
    ) -> [CompactReaderBottomBarAction] {
        var actions: [CompactReaderBottomBarAction] = [hasArchiveFolder ? .archive : .trash]
        if hasMoveTargets { actions.append(.move) }
        actions.append(contentsOf: [.replyMenu, .compose])
        return actions
    }

    /// The sections of the merged ••• menu, in display order.
    static func overflowSections(
        hasRelatedMail: Bool,
        showsRenderingToggle: Bool,
        canAskAI: Bool
    ) -> [CompactReaderOverflowSection] {
        var sections: [CompactReaderOverflowSection] = []
        if hasRelatedMail { sections.append(.relatedMail) }
        if showsRenderingToggle { sections.append(.renderingToggle) }
        sections.append(.messageActions)
        if canAskAI { sections.append(.askAI) }
        return sections
    }
}
