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

import BrevAI
import BrevBackend
@testable import BrevMail
import Foundation
import Testing

@Suite("MailMessageCommandActions")
struct MailMessageCommandActionsTests {
    @Test("message command state disables every selected-message command without a selection")
    func messageCommandStateDisablesSelectedMessageCommandsWithoutSelection() {
        let state = MailMessageCommandStatePolicy.state(
            selectedHeader: nil,
            folders: [Self.archiveFolder],
            messageActionsAvailable: true,
            composePresentationAvailable: true
        )

        #expect(state.readToggleTitle == "Mark as Read")
        #expect(state.flagToggleTitle == "Flag")
        #expect(!state.canReply)
        #expect(!state.canReplyAll)
        #expect(!state.canForward)
        #expect(!state.canToggleRead)
        #expect(!state.canToggleFlag)
        #expect(!state.canArchive)
        #expect(!state.canMove)
        #expect(state.junkActionTitle == nil)
        #expect(!state.canSetJunk)
        #expect(!state.canDelete)
    }

    @Test("message command state enables supported commands for a selected message")
    func messageCommandStateEnablesSupportedCommandsForSelectedMessage() {
        let state = MailMessageCommandStatePolicy.state(
            selectedHeader: Self.makeHeader(isRead: true, isFlagged: true),
            folders: [Self.inboxFolder, Self.archiveFolder, Self.spamFolder],
            backendCapabilities: [.junkAPI],
            messageActionsAvailable: true,
            composePresentationAvailable: true
        )

        #expect(state.readToggleTitle == "Mark as Unread")
        #expect(state.flagToggleTitle == "Unflag")
        #expect(state.canReply)
        #expect(state.canReplyAll)
        #expect(state.canForward)
        #expect(state.canToggleRead)
        #expect(state.canToggleFlag)
        #expect(state.canArchive)
        #expect(state.canMove)
        #expect(state.junkActionTitle == "Report Junk")
        #expect(state.canSetJunk)
        #expect(state.canDelete)
    }

    @Test("message command state exposes not-junk in spam with folder fallback")
    func messageCommandStateExposesNotJunkInSpamWithFolderFallback() {
        let state = MailMessageCommandStatePolicy.state(
            selectedHeader: Self.makeHeader(folderID: Self.spamFolder.id),
            folders: [Self.inboxFolder, Self.spamFolder],
            messageActionsAvailable: true,
            composePresentationAvailable: true
        )

        #expect(state.junkActionTitle == "Not Junk")
        #expect(state.canSetJunk)
    }

    @Test("message command state disables unsupported or blocked focused actions")
    func messageCommandStateDisablesUnsupportedOrBlockedFocusedActions() {
        let header = Self.makeHeader()
        let unsupported = MailMessageCommandStatePolicy.state(
            selectedHeader: header,
            folders: [],
            messageActionsAvailable: false,
            composePresentationAvailable: false
        )

        #expect(!unsupported.canReply)
        #expect(!unsupported.canReplyAll)
        #expect(!unsupported.canForward)
        #expect(!unsupported.canToggleRead)
        #expect(!unsupported.canToggleFlag)
        #expect(!unsupported.canArchive)
        #expect(!unsupported.canMove)
        #expect(!unsupported.canSetJunk)
        #expect(!unsupported.canDelete)

        let noArchiveFolder = MailMessageCommandStatePolicy.state(
            selectedHeader: header,
            folders: [],
            messageActionsAvailable: true,
            composePresentationAvailable: true
        )

        #expect(noArchiveFolder.canReply)
        #expect(noArchiveFolder.canReplyAll)
        #expect(noArchiveFolder.canForward)
        #expect(noArchiveFolder.canToggleRead)
        #expect(noArchiveFolder.canToggleFlag)
        #expect(!noArchiveFolder.canArchive)
        #expect(!noArchiveFolder.canMove)
        #expect(!noArchiveFolder.canSetJunk)
        #expect(noArchiveFolder.canDelete)
    }

    @Test("message command actions invoke root-owned closures with the selected header")
    @MainActor
    func messageCommandActionsInvokeRootOwnedClosures() async {
        let header = Self.makeHeader()
        var invoked: [String] = []
        let actions = MailMessageCommandActions(
            toggleRead: { invoked.append("read:\($0.id)") },
            toggleStar: { invoked.append("flag:\($0.id)") },
            archive: { invoked.append("archive:\($0.id)") },
            move: { header, destination in invoked.append("move:\(header.id)->\(destination.id)") },
            setJunk: { header, isJunk in invoked.append("junk:\(header.id)->\(isJunk)") },
            delete: { invoked.append("delete:\($0.id)") }
        )

        await actions.toggleRead(header)
        await actions.toggleStar(header)
        await actions.archive(header)
        await actions.move(header, to: Self.archiveFolder)
        await actions.setJunk(true, for: header)
        await actions.delete(header)

        #expect(invoked == [
            "read:message-1",
            "flag:message-1",
            "archive:message-1",
            "move:message-1->archive",
            "junk:message-1->true",
            "delete:message-1"
        ])
    }

    @Test("message command actions expose pending mutation state")
    @MainActor
    func messageCommandActionsExposePendingMutationState() {
        let actions = MailMessageCommandActions(
            isPerformingMutation: true,
            toggleRead: { _ in },
            toggleStar: { _ in },
            archive: { _ in },
            move: { _, _ in },
            setJunk: { _, _ in },
            delete: { _ in }
        )

        #expect(actions.isPerformingMutation)
        #expect(!actions.isAvailable)
    }

    @Test("message command actions expose blocked state")
    @MainActor
    func messageCommandActionsExposeBlockedState() {
        let actions = MailMessageCommandActions(
            isBlocked: true,
            toggleRead: { _ in },
            toggleStar: { _ in },
            archive: { _ in },
            move: { _, _ in },
            setJunk: { _, _ in },
            delete: { _ in }
        )

        #expect(actions.isBlocked)
        #expect(!actions.isAvailable)
    }

    @Test("unavailable message command actions do not invoke closures")
    @MainActor
    func unavailableMessageCommandActionsDoNotInvokeClosures() async {
        let header = Self.makeHeader()
        var invoked: [String] = []
        let pending = MailMessageCommandActions(
            isPerformingMutation: true,
            toggleRead: { invoked.append("read:\($0.id)") },
            toggleStar: { invoked.append("flag:\($0.id)") },
            archive: { invoked.append("archive:\($0.id)") },
            move: { invoked.append("move:\($0.id)->\($1.id)") },
            setJunk: { invoked.append("junk:\($0.id)->\($1)") },
            delete: { invoked.append("delete:\($0.id)") }
        )
        let blocked = MailMessageCommandActions(
            isBlocked: true,
            toggleRead: { invoked.append("read:\($0.id)") },
            toggleStar: { invoked.append("flag:\($0.id)") },
            archive: { invoked.append("archive:\($0.id)") },
            move: { invoked.append("move:\($0.id)->\($1.id)") },
            setJunk: { invoked.append("junk:\($0.id)->\($1)") },
            delete: { invoked.append("delete:\($0.id)") }
        )

        await pending.toggleRead(header)
        await pending.toggleStar(header)
        await pending.archive(header)
        await pending.move(header, to: Self.archiveFolder)
        await pending.setJunk(true, for: header)
        await pending.delete(header)
        await blocked.toggleRead(header)
        await blocked.toggleStar(header)
        await blocked.archive(header)
        await blocked.move(header, to: Self.archiveFolder)
        await blocked.setJunk(false, for: header)
        await blocked.delete(header)

        #expect(invoked.isEmpty)
    }

    @Test("mailbox action agent action exposes availability and invokes presentation")
    @MainActor
    func mailboxActionAgentActionExposesAvailabilityAndInvokesPresentation() {
        var presentationCount = 0
        let actions = MailMailboxActionAgentActions(
            isBlocked: false
        ) {
            presentationCount += 1
        }

        #expect(actions.isAvailable)

        actions.present()

        #expect(presentationCount == 1)
    }

    @Test("blocked mailbox action agent action does not invoke presentation")
    @MainActor
    func blockedMailboxActionAgentActionDoesNotInvokePresentation() {
        var presentationCount = 0
        let actions = MailMailboxActionAgentActions(
            isBlocked: true
        ) {
            presentationCount += 1
        }

        #expect(!actions.isAvailable)

        actions.present()

        #expect(presentationCount == 0)
    }

    @Test("hidden mailbox action agent action is not available and does not invoke presentation")
    @MainActor
    func hiddenMailboxActionAgentActionIsNotAvailableAndDoesNotInvokePresentation() {
        var presentationCount = 0
        let actions = MailMailboxActionAgentActions(
            isVisible: false,
            isBlocked: false
        ) {
            presentationCount += 1
        }

        #expect(!actions.isVisible)
        #expect(!actions.isAvailable)

        actions.present()

        #expect(presentationCount == 0)
    }

    private static let inboxFolder = Folder(id: "inbox", name: "Inbox", role: .inbox)
    private static let archiveFolder = Folder(id: "archive", name: "Archive", role: .archive)
    private static let spamFolder = Folder(id: "spam", name: "Spam", role: .spam)

    private static func makeHeader(
        isRead: Bool = false,
        isFlagged: Bool = false,
        folderID: Folder.ID = inboxFolder.id
    ) -> MessageHeader {
        MessageHeader(
            id: "message-1",
            threadID: "thread-1",
            folderID: folderID,
            from: Correspondent(name: "Alex", email: "alex@example.org"),
            subject: "Hello",
            snippet: "Preview",
            date: Date(timeIntervalSince1970: 1_779_960_600),
            isRead: isRead,
            isFlagged: isFlagged
        )
    }
}

@Suite("MailboxActionAgentAvailabilityPolicy")
struct MailboxActionAgentAvailabilityPolicyTests {
    @Test("availability requires mailbox-action consent and an AI backend")
    func availabilityRequiresMailboxActionConsentAndAIBackend() {
        let enabled = MailboxActionAgentSettings(isEnabled: true, consentGiven: true)

        #expect(!MailboxActionAgentAvailabilityPolicy.isVisible(
            settings: .defaults,
            hasAIBackend: true,
            backendSupportsAIIntent: true
        ))
        #expect(!MailboxActionAgentAvailabilityPolicy.isVisible(
            settings: enabled,
            hasAIBackend: false,
            backendSupportsAIIntent: true
        ))
        #expect(!MailboxActionAgentAvailabilityPolicy.isVisible(
            settings: enabled,
            hasAIBackend: true,
            backendSupportsAIIntent: false
        ))
        #expect(MailboxActionAgentAvailabilityPolicy.isVisible(
            settings: enabled,
            hasAIBackend: true,
            backendSupportsAIIntent: true
        ))
    }

    @Test("presentation still respects mailbox navigation and busy state")
    func presentationStillRespectsMailboxNavigationAndBusyState() {
        let enabled = MailboxActionAgentSettings(isEnabled: true, consentGiven: true)

        #expect(MailboxActionAgentAvailabilityPolicy.canPresent(
            settings: enabled,
            hasAIBackend: true,
            backendSupportsAIIntent: true,
            hasSelectedFolder: true,
            hasActionFolders: true,
            hasActiveWork: false,
            hasPresentedSheet: false,
            isUnifiedInboxSelected: false,
            isSmartViewSelected: false
        ))
        #expect(!MailboxActionAgentAvailabilityPolicy.canPresent(
            settings: enabled,
            hasAIBackend: true,
            backendSupportsAIIntent: true,
            hasSelectedFolder: false,
            hasActionFolders: true,
            hasActiveWork: false,
            hasPresentedSheet: false,
            isUnifiedInboxSelected: false,
            isSmartViewSelected: false
        ))
        #expect(!MailboxActionAgentAvailabilityPolicy.canPresent(
            settings: enabled,
            hasAIBackend: true,
            backendSupportsAIIntent: true,
            hasSelectedFolder: true,
            hasActionFolders: true,
            hasActiveWork: true,
            hasPresentedSheet: false,
            isUnifiedInboxSelected: false,
            isSmartViewSelected: false
        ))
        #expect(!MailboxActionAgentAvailabilityPolicy.canPresent(
            settings: enabled,
            hasAIBackend: true,
            backendSupportsAIIntent: true,
            hasSelectedFolder: true,
            hasActionFolders: true,
            hasActiveWork: false,
            hasPresentedSheet: false,
            isUnifiedInboxSelected: true,
            isSmartViewSelected: false
        ))
    }
}
