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
@testable import BrevMail
import Foundation
import Testing

@Suite("MessageCommandPresentation")
struct MessageCommandPresentationTests {
    @Test("read toggle title matches next action")
    func readToggleTitleMatchesNextAction() {
        #expect(MessageCommandPresentation.readToggleTitle(for: Self.makeHeader(isRead: false)) == "Mark as Read")
        #expect(MessageCommandPresentation.readToggleTitle(for: Self.makeHeader(isRead: true)) == "Mark as Unread")
    }

    @Test("flag title and symbol reflect flagged state")
    func flagTitleAndSymbolReflectFlaggedState() {
        let unflagged = Self.makeHeader(isFlagged: false)
        let flagged = Self.makeHeader(isFlagged: true)

        #expect(MessageCommandPresentation.flagToggleTitle(for: unflagged) == "Flag")
        #expect(MessageCommandPresentation.flagToggleSymbolName(for: unflagged) == "flag")
        #expect(MessageCommandPresentation.flagToggleTitle(for: flagged) == "Unflag")
        #expect(MessageCommandPresentation.flagToggleSymbolName(for: flagged) == "flag.slash")
    }

    @Test("move folder candidates omit the current folder")
    func moveFolderCandidatesOmitTheCurrentFolder() {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let archive = Folder(id: "archive", name: "Archive", role: .archive)
        let receipts = Folder(id: "receipts", name: "Receipts", role: .custom)

        let candidates = MessageCommandPresentation.moveFolderCandidates(
            from: [inbox, archive, receipts],
            currentFolderID: inbox.id
        )

        #expect(candidates == [archive, receipts])
    }

    @Test("move folder candidates are empty when only the current folder exists")
    func moveFolderCandidatesAreEmptyWhenOnlyTheCurrentFolderExists() {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)

        #expect(MessageCommandPresentation.moveFolderCandidates(
            from: [inbox],
            currentFolderID: inbox.id
        ).isEmpty)
    }

    @Test("junk action title falls back to spam and inbox folders without provider junk API")
    func junkActionTitleFallsBackToSpamAndInboxFoldersWithoutProviderJunkAPI() {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let spam = Folder(id: "spam", name: "Spam", role: .spam)

        #expect(MessageCommandPresentation.junkActionTitle(
            currentFolder: inbox,
            capabilities: [],
            folders: [inbox, spam]
        ) == "Report Junk")
        #expect(MessageCommandPresentation.junkActionTitle(
            currentFolder: spam,
            capabilities: [],
            folders: [inbox, spam]
        ) == "Not Junk")
        #expect(MessageCommandPresentation.junkActionTitle(
            currentFolder: inbox,
            capabilities: [],
            folders: [inbox]
        ) == nil)
    }

    @Test("junk fallback folder uses spam for junk and inbox for not junk")
    func junkFallbackFolderUsesSpamForJunkAndInboxForNotJunk() {
        let inbox = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let spam = Folder(id: "spam", name: "Spam", role: .spam)

        #expect(MessageCommandPresentation.junkFallbackFolder(
            isJunk: true,
            folders: [inbox, spam]
        ) == spam)
        #expect(MessageCommandPresentation.junkFallbackFolder(
            isJunk: false,
            folders: [inbox, spam]
        ) == inbox)
        #expect(MessageCommandPresentation.junkFallbackFolder(
            isJunk: true,
            folders: [inbox]
        ) == nil)
    }

    @Test("direct message actions request platform feedback")
    func directMessageActionsRequestPlatformFeedback() {
        #expect(MessageCommandPresentation.feedback(for: .toggleRead) == .impact)
        #expect(MessageCommandPresentation.feedback(for: .toggleFlag) == .impact)
        #expect(MessageCommandPresentation.feedback(for: .archive) == .impact)
        #expect(MessageCommandPresentation.feedback(for: .move) == .impact)
        #expect(MessageCommandPresentation.feedback(for: .delete) == .warning)
    }

    @Test("swipe action order keeps non-destructive actions as full-swipe defaults")
    func swipeActionOrderKeepsNonDestructiveActionsAsFullSwipeDefaults() {
        #expect(MessageCommandPresentation.trailingSwipeActions(hasArchive: true) == [.archive, .delete])
        #expect(MessageCommandPresentation.trailingSwipeActions(hasArchive: false) == [.delete])
        #expect(MessageCommandPresentation.leadingSwipeActions == [.toggleFlag, .toggleRead])
    }

    @Test("detail context actions expose local sheets without requiring move targets")
    func detailContextActionsExposeLocalSheetsWithoutRequiringMoveTargets() {
        #expect(MessageCommandPresentation.detailContextActions(
            canPresentSheets: true,
            hasMoveTargets: false
        ) == [.createTask, .addNote, .followUp])
        #expect(MessageCommandPresentation.detailContextActions(
            canPresentSheets: true,
            hasMoveTargets: true
        ) == [.createTask, .addNote, .followUp, .move])
        #expect(MessageCommandPresentation.detailContextActions(
            canPresentSheets: false,
            hasMoveTargets: true
        ).isEmpty)
    }

    @Test("message context menu hides actions with no backing capability")
    func messageContextMenuHidesActionsWithNoBackingCapability() {
        let header = Self.makeHeader(isRead: false, isFlagged: false)
        let menu = MessageCommandPresentation.contextMenu(
            for: header,
            isSelected: false,
            isPinned: false,
            isSnoozed: false,
            isDone: false,
            canOpenInNewWindow: true,
            canArchive: true,
            canMove: true,
            junkActionTitle: "Report Junk",
            canBlockSender: true,
            canDelete: true
        )

        // With no extended capabilities, Copy to Folder, Save As, View Source,
        // and Show Headers are hidden — not shown disabled (#262 honesty pass).
        // Add Note, Create Rule, Create Meeting, and Keep Offline are wired
        // locally (#268).
        #expect(menu.sections.map { $0.actions.map(\.action) } == [
            [.openInNewWindow],
            [.select, .pinToTop],
            [.toggleRead, .toggleFlag, .toggleSnooze, .toggleDone],
            [.reply, .replyAll, .forward],
            [.archive, .move, .setJunk, .blockSender, .delete],
            [.print, .exportPDF, .downloadOffline],
            [.createTask, .createRule, .createMeeting, .addNote, .followUp],
            [.properties]
        ])
        #expect(menu.action(.toggleRead)?.title == "Mark as Read")
        #expect(menu.action(.toggleFlag)?.symbolName == "flag")
        #expect(menu.action(.copyToFolder) == nil)
        #expect(menu.action(.saveAs) == nil)
        #expect(menu.action(.showHeaders) == nil)
        #expect(menu.action(.viewSource) == nil)
        #expect(menu.action(.createMeeting)?.title == "Create Meeting from Message…")
        #expect(menu.action(.createRule)?.title == "Create Rule from Message…")
        #expect(menu.action(.addNote)?.title == "Add Note…")
        #expect(menu.action(.downloadOffline)?.title == "Keep Offline")
        #expect(menu.action(.followUp)?.title == "Set Follow-Up Reminder…")
    }

    @Test("Add Note toggles its title when the message already has a local note")
    func addNoteTitleReflectsExistingNote() {
        let header = Self.makeHeader(isRead: false, isFlagged: false)
        func title(hasNote: Bool) -> String? {
            MessageCommandPresentation.contextMenu(
                for: header,
                isSelected: false,
                isPinned: false,
                isSnoozed: false,
                isDone: false,
                hasNote: hasNote,
                canOpenInNewWindow: true,
                canArchive: true,
                canMove: true,
                junkActionTitle: "Report Junk",
                canBlockSender: true,
                canDelete: true
            ).action(.addNote)?.title
        }

        #expect(title(hasNote: false) == "Add Note…")
        #expect(title(hasNote: true) == "Edit Note…")
    }

    @Test("Keep Offline toggles its title when the message is pinned offline (#268)")
    func keepOfflineTitleReflectsPinState() {
        let header = Self.makeHeader(isRead: false, isFlagged: false)
        func title(isKeptOffline: Bool) -> String? {
            MessageCommandPresentation.contextMenu(
                for: header,
                isSelected: false,
                isPinned: false,
                isSnoozed: false,
                isDone: false,
                isKeptOffline: isKeptOffline,
                canOpenInNewWindow: true,
                canArchive: true,
                canMove: true,
                junkActionTitle: "Report Junk",
                canBlockSender: true,
                canDelete: true
            ).action(.downloadOffline)?.title
        }
        #expect(title(isKeptOffline: false) == "Keep Offline")
        #expect(title(isKeptOffline: true) == "Stop Keeping Offline")
    }

    @Test("raw-source capability surfaces View Source and Show Headers, enabled")
    func rawSourceCapabilitySurfacesViewSourceAndShowHeaders() {
        let menu = MessageCommandPresentation.contextMenu(
            for: Self.makeHeader(),
            isSelected: false,
            isPinned: false,
            isSnoozed: false,
            isDone: false,
            canOpenInNewWindow: false,
            canArchive: false,
            canMove: false,
            junkActionTitle: nil,
            canBlockSender: false,
            canDelete: true,
            canShowProperties: true,
            extendedCapabilities: [.rawMessageSource]
        )

        #expect(menu.action(.viewSource)?.isEnabled == true)
        #expect(menu.action(.showHeaders)?.isEnabled == true)
        // Save As needs the platform export gate (`canExportEML`) in addition to
        // the raw-source capability.
        #expect(menu.action(.saveAs) == nil)
        #expect(menu.action(.properties)?.action == .properties)
    }

    @Test("Save As requires original bytes and the platform export gate")
    func saveAsAppearsOnlyWithRawSourceAndExportGate() {
        func menu(originalBytes: Bool, rawSource: Bool = true, exportEML: Bool) -> MessageContextMenuPresentation {
            var capabilities: BackendExtendedCapabilities = rawSource ? [.rawMessageSource] : []
            if originalBytes { capabilities.insert(.rawMessageBytes) }
            return MessageCommandPresentation.contextMenu(
                for: Self.makeHeader(),
                isSelected: false,
                isPinned: false,
                isSnoozed: false,
                isDone: false,
                canOpenInNewWindow: false,
                canArchive: false,
                canMove: false,
                junkActionTitle: nil,
                canBlockSender: false,
                canDelete: true,
                extendedCapabilities: capabilities,
                canExportEML: exportEML
            )
        }

        #expect(menu(originalBytes: true, rawSource: false, exportEML: true).action(.saveAs)?.isEnabled == true)
        #expect(menu(originalBytes: true, exportEML: false).action(.saveAs) == nil)
        #expect(menu(originalBytes: false, exportEML: true).action(.saveAs) == nil)
    }

    @Test("Copy to Folder needs both the copy capability and a move target")
    func copyToFolderNeedsCapabilityAndTarget() {
        func menu(copy: Bool, canMove: Bool) -> MessageContextMenuPresentation {
            MessageCommandPresentation.contextMenu(
                for: Self.makeHeader(),
                isSelected: false,
                isPinned: false,
                isSnoozed: false,
                isDone: false,
                canOpenInNewWindow: false,
                canArchive: false,
                canMove: canMove,
                junkActionTitle: nil,
                canBlockSender: false,
                canDelete: true,
                extendedCapabilities: copy ? [.messageCopy] : []
            )
        }

        #expect(menu(copy: true, canMove: true).action(.copyToFolder)?.isEnabled == true)
        #expect(menu(copy: true, canMove: false).action(.copyToFolder) == nil)
        #expect(menu(copy: false, canMove: true).action(.copyToFolder) == nil)
    }

    @Test("print, export PDF, and properties enable when their backing is available")
    func printExportAndPropertiesEnableWhenBackingIsAvailable() {
        let menu = MessageCommandPresentation.contextMenu(
            for: Self.makeHeader(),
            isSelected: false,
            isPinned: false,
            isSnoozed: false,
            isDone: false,
            canOpenInNewWindow: false,
            canArchive: false,
            canMove: false,
            junkActionTitle: nil,
            canBlockSender: false,
            canDelete: true,
            canPrint: true,
            canExportPDF: true,
            canShowProperties: true
        )

        #expect(menu.action(.print)?.isEnabled == true)
        #expect(menu.action(.exportPDF)?.isEnabled == true)
        #expect(menu.action(.properties)?.isEnabled == true)
    }

    @Test("message EML export preserves original bytes and uses a safe subject filename")
    func messageEMLExportPreservesOriginalBytes() throws {
        let header = Self.makeHeader(subject: "Invoice/June: <draft>?")
        let raw = Data("Content-Type: text/plain; charset=iso-8859-1\r\n\r\n".utf8) + Data([0xE5, 0xF8, 0xE6])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brev-eml-\(UUID().uuidString).eml")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(MessageEMLExport.fileName(for: header) == "Invoice-June- -draft--.eml")
        try MessageEMLExport.write(raw, to: url)
        #expect(try Data(contentsOf: url) == raw)
    }

    @Test("message EML export never produces a dotfile or reserved name")
    func messageEMLExportAvoidsLeadingDotNames() {
        #expect(MessageEMLExport.fileName(for: Self.makeHeader(subject: "..")) == "message.eml")
        #expect(MessageEMLExport.fileName(for: Self.makeHeader(subject: ".hidden")) == "hidden.eml")
        #expect(MessageEMLExport.fileName(for: Self.makeHeader(subject: "   ")) == "message.eml")
    }

    @Test("message context menu keeps mailbox and unified inbox policy aligned")
    func messageContextMenuKeepsMailboxAndUnifiedInboxPolicyAligned() {
        let header = Self.makeHeader(isRead: true, isFlagged: true)
        let mailboxMenu = MessageCommandPresentation.contextMenu(
            for: header,
            isSelected: true,
            isPinned: true,
            isSnoozed: true,
            isDone: true,
            canOpenInNewWindow: false,
            canArchive: false,
            canMove: true,
            junkActionTitle: nil,
            canBlockSender: false,
            canDelete: true
        )
        let unifiedMenu = MessageCommandPresentation.contextMenu(
            for: header,
            isSelected: true,
            isPinned: true,
            isSnoozed: true,
            isDone: true,
            canOpenInNewWindow: false,
            canArchive: false,
            canMove: true,
            junkActionTitle: nil,
            canBlockSender: false,
            canDelete: true
        )

        #expect(mailboxMenu == unifiedMenu)
        #expect(mailboxMenu.action(.openInNewWindow) == nil)
        #expect(mailboxMenu.action(.archive) == nil)
        #expect(mailboxMenu.action(.setJunk) == nil)
        #expect(mailboxMenu.action(.select)?.title == "Deselect")
        #expect(mailboxMenu.action(.pinToTop)?.title == "Unpin")
        #expect(mailboxMenu.action(.toggleSnooze)?.title == "Unsnooze")
        #expect(mailboxMenu.action(.toggleDone)?.title == "Mark as Not Done")
    }

    @Test("mutation errors include a refresh action and localized message")
    func mutationErrorsIncludeRefreshActionAndLocalizedMessage() {
        #expect(MessageCommandPresentation.mutationErrorStatus(
            for: MailBackendError.network(underlying: "offline")
        ) == MailRootStatus(
            message: "Network error: offline",
            actionTitle: "Refresh"
        ))
    }

    private static func makeHeader(
        isRead: Bool = false,
        isFlagged: Bool = false,
        subject: String = "Hello"
    ) -> MessageHeader {
        MessageHeader(
            id: "m1",
            threadID: "t1",
            folderID: "inbox",
            from: Correspondent(name: "Alex", email: "alex@example.org"),
            subject: subject,
            snippet: "Preview",
            date: Date(timeIntervalSince1970: 1_779_960_600),
            isRead: isRead,
            isFlagged: isFlagged
        )
    }
}
