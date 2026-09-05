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

#if os(macOS)
import AppKit
import BrevBackend
@testable import BrevMail
import Foundation
import Testing

@Suite("BrevMailNativeToolbar")
@MainActor
struct BrevMailNativeToolbarTests {
    /// The native toolbar must stay opt-in: it replaces `window.toolbar`, which
    /// breaks the KVO registration SwiftUI keeps for the `.searchable` field and
    /// crashes on launch. Regression guard for that default.
    @Test("the native toolbar stays opt-in")
    func theNativeToolbarStaysOptIn() {
        #expect(!BrevMailToolbarRuntime.usesNativeToolbar(environment: [:]))
        #expect(!BrevMailToolbarRuntime.usesNativeToolbar(environment: ["BREV_ENABLE_NATIVE_TOOLBAR": "0"]))
        #expect(BrevMailToolbarRuntime.usesNativeToolbar(environment: ["BREV_ENABLE_NATIVE_TOOLBAR": "1"]))
    }

    @Test("message actions are disabled until a header is selected")
    func messageActionsRequireSelectedHeader() {
        let state = BrevMailNativeToolbarState(
            selectedHeader: nil,
            hasSelectedFolder: true,
            canArchive: true
        )

        #expect(state.isEnabled(.compose))
        #expect(state.isEnabled(.refresh))
        #expect(!state.isEnabled(.reply))
        #expect(!state.isEnabled(.replyAll))
        #expect(!state.isEnabled(.forward))
        #expect(!state.isEnabled(.read))
        #expect(!state.isEnabled(.flag))
        #expect(!state.isEnabled(.archive))
        #expect(!state.isEnabled(.delete))
        #expect(state.isEnabled(.settings))
    }

    @Test("archive follows archive folder availability")
    func archiveFollowsArchiveFolderAvailability() {
        let withoutArchive = BrevMailNativeToolbarState(
            selectedHeader: Self.makeHeader(),
            hasSelectedFolder: true,
            canArchive: false
        )
        let withArchive = BrevMailNativeToolbarState(
            selectedHeader: Self.makeHeader(),
            hasSelectedFolder: true,
            canArchive: true
        )

        #expect(!withoutArchive.isEnabled(.archive))
        #expect(withArchive.isEnabled(.archive))
    }

    @Test("pending refresh disables toolbar refresh")
    func pendingRefreshDisablesToolbarRefresh() {
        let state = BrevMailNativeToolbarState(
            selectedHeader: nil,
            hasSelectedFolder: true,
            canArchive: false,
            isRefreshing: true
        )

        #expect(!state.isEnabled(.refresh))
        #expect(state.isEnabled(.compose))
        #expect(state.isEnabled(.settings))
    }

    @Test("pending refresh disables toolbar mutation actions")
    func pendingRefreshDisablesToolbarMutationActions() {
        let state = BrevMailNativeToolbarState(
            selectedHeader: Self.makeHeader(),
            hasSelectedFolder: true,
            canArchive: true,
            isRefreshing: true
        )

        #expect(!state.isEnabled(.read))
        #expect(!state.isEnabled(.flag))
        #expect(!state.isEnabled(.archive))
        #expect(!state.isEnabled(.delete))
    }

    @Test("pending mailbox switch disables toolbar refresh")
    func pendingMailboxSwitchDisablesToolbarRefresh() {
        let state = BrevMailNativeToolbarState(
            selectedHeader: nil,
            hasSelectedFolder: true,
            canArchive: false,
            isSwitchingMailbox: true,
            isComposeBlocked: true
        )

        #expect(!state.isEnabled(.refresh))
        #expect(!state.isEnabled(.compose))
        #expect(state.isEnabled(.settings))
    }

    @Test("pending mailbox switch disables toolbar mutation actions")
    func pendingMailboxSwitchDisablesToolbarMutationActions() {
        let state = BrevMailNativeToolbarState(
            selectedHeader: Self.makeHeader(),
            hasSelectedFolder: true,
            canArchive: true,
            isSwitchingMailbox: true
        )

        #expect(!state.isEnabled(.read))
        #expect(!state.isEnabled(.flag))
        #expect(!state.isEnabled(.archive))
        #expect(!state.isEnabled(.delete))
    }

    @Test("pending command mutation disables toolbar mutation actions")
    func pendingCommandMutationDisablesToolbarMutationActions() {
        let state = BrevMailNativeToolbarState(
            selectedHeader: Self.makeHeader(),
            hasSelectedFolder: true,
            canArchive: true,
            isPerformingCommandMutation: true,
            isComposeBlocked: true
        )

        #expect(!state.isEnabled(.compose))
        #expect(!state.isEnabled(.refresh))
        #expect(!state.isEnabled(.reply))
        #expect(!state.isEnabled(.replyAll))
        #expect(!state.isEnabled(.forward))
        #expect(!state.isEnabled(.read))
        #expect(!state.isEnabled(.flag))
        #expect(!state.isEnabled(.archive))
        #expect(!state.isEnabled(.delete))
        #expect(state.isEnabled(.settings))
    }

    @Test("compose block disables toolbar compose presentation actions")
    func composeBlockDisablesToolbarComposePresentationActions() {
        let state = BrevMailNativeToolbarState(
            selectedHeader: Self.makeHeader(),
            hasSelectedFolder: true,
            canArchive: true,
            isComposeBlocked: true
        )

        #expect(!state.isEnabled(.compose))
        #expect(!state.isEnabled(.reply))
        #expect(!state.isEnabled(.replyAll))
        #expect(!state.isEnabled(.forward))
        #expect(state.isEnabled(.read))
        #expect(state.isEnabled(.flag))
        #expect(state.isEnabled(.archive))
        #expect(state.isEnabled(.delete))
        #expect(state.isEnabled(.settings))
    }

    @Test("presented sheets disable toolbar settings")
    func presentedSheetsDisableToolbarSettings() {
        let state = BrevMailNativeToolbarState(
            selectedHeader: Self.makeHeader(),
            hasSelectedFolder: true,
            canArchive: true,
            hasPresentedSheet: true,
            isSettingsBlocked: true
        )

        #expect(!state.isEnabled(.settings))
    }

    @Test("external settings stay available while mail sheets are active")
    func externalSettingsStayAvailableWhileMailSheetsAreActive() {
        let state = BrevMailNativeToolbarState(
            selectedHeader: Self.makeHeader(),
            hasSelectedFolder: true,
            canArchive: true,
            hasPresentedSheet: true,
            usesExternalSettingsWindow: true
        )

        #expect(state.isEnabled(.settings))
    }

    @Test("presented sheets disable toolbar refresh and mutation actions")
    func presentedSheetsDisableToolbarRefreshAndMutationActions() {
        let state = BrevMailNativeToolbarState(
            selectedHeader: Self.makeHeader(),
            hasSelectedFolder: true,
            canArchive: true,
            hasPresentedSheet: true
        )

        #expect(!state.isEnabled(.refresh))
        #expect(!state.isEnabled(.read))
        #expect(!state.isEnabled(.flag))
        #expect(!state.isEnabled(.archive))
        #expect(!state.isEnabled(.delete))
    }

    @Test("disabled toolbar items cannot be invoked directly")
    func disabledToolbarItemsCannotBeInvokedDirectly() {
        let state = BrevMailNativeToolbarState(
            selectedHeader: Self.makeHeader(),
            hasSelectedFolder: true,
            canArchive: true,
            isPerformingCommandMutation: true,
            isSettingsBlocked: true
        )

        #expect(!state.canInvoke(.refresh))
        #expect(!state.canInvoke(.read))
        #expect(!state.canInvoke(.flag))
        #expect(!state.canInvoke(.settings))
        #expect(state.messageHeaderForInvocation(.read) == nil)
        #expect(state.messageHeaderForInvocation(.flag) == nil)
        #expect(state.messageHeaderForInvocation(.archive) == nil)
        #expect(state.messageHeaderForInvocation(.delete) == nil)
    }

    @Test("enabled message toolbar items expose their invocation header")
    func enabledMessageToolbarItemsExposeTheirInvocationHeader() {
        let header = Self.makeHeader()
        let state = BrevMailNativeToolbarState(
            selectedHeader: header,
            hasSelectedFolder: true,
            canArchive: true
        )

        #expect(state.canInvoke(.flag))
        #expect(state.messageHeaderForInvocation(.reply) == header)
        #expect(state.messageHeaderForInvocation(.replyAll) == header)
        #expect(state.messageHeaderForInvocation(.forward) == header)
        #expect(state.messageHeaderForInvocation(.read) == header)
        #expect(state.messageHeaderForInvocation(.flag) == header)
        #expect(state.messageHeaderForInvocation(.archive) == header)
        #expect(state.messageHeaderForInvocation(.delete) == header)
    }

    @Test("native toolbar keeps the AI Sidebar item in its default controls")
    func nativeToolbarKeepsMailContextItem() {
        let coordinator = BrevMailNativeToolbarBridge.Coordinator(
            state: BrevMailNativeToolbarState(
                selectedHeader: nil,
                hasSelectedFolder: true,
                canArchive: true
            ),
            actions: BrevMailNativeToolbarActions(
                compose: {},
                refresh: {},
                reply: { _ in },
                replyAll: { _ in },
                forward: { _ in },
                toggleRead: { _ in },
                toggleStar: { _ in },
                archive: { _ in },
                delete: { _ in },
                settings: {},
                toggleMailContext: {}
            )
        )
        let identifiers = coordinator
            .toolbarDefaultItemIdentifiers(NSToolbar(identifier: "test"))
            .map(\.rawValue)

        #expect(identifiers == [
            "app.brev.mail.compose",
            "app.brev.mail.refresh",
            "NSToolbarFlexibleSpaceItem",
            "app.brev.mail.reply",
            "app.brev.mail.replyAll",
            "app.brev.mail.forward",
            "app.brev.mail.archive",
            "app.brev.mail.delete",
            "NSToolbarFlexibleSpaceItem",
            "app.brev.mail.mailContext",
        ])
    }

    @Test("AI Sidebar is a native customizable toolbar item")
    func aiSidebarIsNativeToolbarItem() {
        let coordinator = BrevMailNativeToolbarBridge.Coordinator(
            state: BrevMailNativeToolbarState(
                selectedHeader: nil,
                hasSelectedFolder: true,
                canArchive: true
            ),
            actions: BrevMailNativeToolbarActions(
                compose: {},
                refresh: {},
                reply: { _ in },
                replyAll: { _ in },
                forward: { _ in },
                toggleRead: { _ in },
                toggleStar: { _ in },
                archive: { _ in },
                delete: { _ in },
                settings: {},
                toggleMailContext: {}
            )
        )

        let identifiers = coordinator
            .toolbarAllowedItemIdentifiers(NSToolbar(identifier: "test"))
            .map(\.rawValue)
        let item = coordinator.toolbar(
            NSToolbar(identifier: "test"),
            itemForItemIdentifier: BrevMailNativeToolbarItem.mailContext.identifier,
            willBeInsertedIntoToolbar: true
        )

        #expect(identifiers.contains("app.brev.mail.mailContext"))
        #expect(item?.view == nil)
    }

    @Test("AI Sidebar native item is placed immediately after Search")
    @MainActor
    func aiSidebarNativeItemFollowsSearch() {
        let items: [NSToolbarItem] = [
            NSToolbarItem(itemIdentifier: BrevMailNativeToolbarItem.settings.identifier),
            NSSearchToolbarItem(itemIdentifier: NSToolbarItem.Identifier("test.search")),
            NSToolbarItem(itemIdentifier: BrevMailNativeToolbarItem.mailContext.identifier),
        ]

        #expect(BrevMailNativeToolbarBridge.desiredMailContextIndex(in: items) == 2)
    }

    @Test("AI Sidebar column takes its width from the reader, not from the window")
    @MainActor
    func aiSidebarTakesWidthFromTheReader() {
        // Toggling the sidebar used to grow the window by the column's width and
        // shrink it back on close, which moved a window the user had sized and
        // placed themselves. The column now has a fixed ideal width that the
        // panes beside it give up, so nothing has to touch the window frame.
        let width = MailPaneColumnWidthPolicy.mailContext(platform: .macOS)

        #expect(width != nil)
        #expect((width?.ideal ?? 0) > 0)
    }

    @Test("AI Sidebar toolbar label reflects inspector visibility")
    func aiSidebarToolbarLabelReflectsInspectorVisibility() {
        let shown = BrevMailNativeToolbarState(
            selectedHeader: nil,
            hasSelectedFolder: true,
            canArchive: true,
            isMailContextPresented: true
        )

        #expect(shown.label(for: .mailContext) == "Hide AI Sidebar")
    }

    @Test("Reply All toolbar item has dedicated label and symbol")
    func replyAllToolbarItemHasDedicatedLabelAndSymbol() {
        let state = BrevMailNativeToolbarState(
            selectedHeader: Self.makeHeader(),
            hasSelectedFolder: true,
            canArchive: true
        )

        #expect(state.label(for: .replyAll) == "Reply All")
        #expect(state.symbolName(for: .replyAll) == "arrowshape.turn.up.left.2")
    }

    @Test("native toolbar defaults include all three response actions")
    func nativeToolbarDefaultsIncludeAllResponseActions() {
        let coordinator = BrevMailNativeToolbarBridge.Coordinator(
            state: BrevMailNativeToolbarState(
                selectedHeader: Self.makeHeader(),
                hasSelectedFolder: true,
                canArchive: true
            ),
            actions: BrevMailNativeToolbarActions(
                compose: {},
                refresh: {},
                reply: { _ in },
                replyAll: { _ in },
                forward: { _ in },
                toggleRead: { _ in },
                toggleStar: { _ in },
                archive: { _ in },
                delete: { _ in },
                settings: {},
                toggleMailContext: {}
            )
        )

        let identifiers = coordinator.toolbarDefaultItemIdentifiers(NSToolbar(identifier: "test"))
        #expect(identifiers.contains(BrevMailNativeToolbarItem.reply.identifier))
        #expect(identifiers.contains(BrevMailNativeToolbarItem.replyAll.identifier))
        #expect(identifiers.contains(BrevMailNativeToolbarItem.forward.identifier))
    }

    @Test("read label and symbol reflect read state")
    func readLabelAndSymbolReflectReadState() {
        let unread = BrevMailNativeToolbarState(
            selectedHeader: Self.makeHeader(isRead: false),
            hasSelectedFolder: true,
            canArchive: true
        )
        let read = BrevMailNativeToolbarState(
            selectedHeader: Self.makeHeader(isRead: true),
            hasSelectedFolder: true,
            canArchive: true
        )

        #expect(unread.label(for: .read) == "Mark as Read")
        #expect(unread.symbolName(for: .read) == "envelope.open")
        #expect(read.label(for: .read) == "Mark as Unread")
        #expect(read.symbolName(for: .read) == "envelope.badge")
    }

    @Test("flag label and symbol reflect flagged state")
    func flagLabelAndSymbolReflectFlaggedState() {
        let unflagged = BrevMailNativeToolbarState(
            selectedHeader: Self.makeHeader(isFlagged: false),
            hasSelectedFolder: true,
            canArchive: true
        )
        let flagged = BrevMailNativeToolbarState(
            selectedHeader: Self.makeHeader(isFlagged: true),
            hasSelectedFolder: true,
            canArchive: true
        )

        #expect(unflagged.label(for: .flag) == "Flag")
        #expect(unflagged.symbolName(for: .flag) == "flag")
        #expect(flagged.label(for: .flag) == "Unflag")
        #expect(flagged.symbolName(for: .flag) == "flag.slash")
    }

    private static func makeHeader(isRead: Bool = false, isFlagged: Bool = false) -> MessageHeader {
        MessageHeader(
            id: "message-1",
            threadID: "thread-1",
            folderID: "inbox",
            from: Correspondent(name: "Alex", email: "alex@example.org"),
            subject: "Hello",
            snippet: "Preview",
            date: Date(timeIntervalSince1970: 1_779_960_600),
            isRead: isRead,
            isFlagged: isFlagged
        )
    }
}
#endif
