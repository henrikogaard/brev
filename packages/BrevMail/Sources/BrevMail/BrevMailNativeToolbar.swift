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
import BrevDesign
import SwiftUI

enum BrevMailNativeToolbarItem: CaseIterable, Hashable {
    case compose
    case refresh
    case reply
    case replyAll
    case forward
    case read
    case flag
    case archive
    case delete
    case createTask
    case followUp
    case move
    case mailContext
    case settings
    case more

    var identifier: NSToolbarItem.Identifier {
        switch self {
        case .compose: return .brevCompose
        case .refresh: return .brevRefresh
        case .reply: return .brevReply
        case .replyAll: return .brevReplyAll
        case .forward: return .brevForward
        case .read: return .brevRead
        case .flag: return .brevFlag
        case .archive: return .brevArchive
        case .delete: return .brevDelete
        case .createTask: return .brevCreateTask
        case .followUp: return .brevFollowUp
        case .move: return .brevMove
        case .mailContext: return .brevMailContext
        case .settings: return .brevSettings
        case .more: return .brevMore
        }
    }

    var label: String {
        switch self {
        case .compose: return "Compose"
        case .refresh: return "Refresh"
        case .reply: return "Reply"
        case .replyAll: return "Reply All"
        case .forward: return "Forward"
        case .read: return "Mark as Read"
        case .flag: return "Flag"
        case .archive: return "Archive"
        case .delete: return "Delete"
        case .createTask: return "Create Task"
        case .followUp: return "Follow Up"
        case .move: return "Move"
        case .mailContext: return MailContextColumnVisibility.toolbarLabel
        case .settings: return "Settings"
        case .more: return "More message actions"
        }
    }

    static let moreMenuItems: [Self] = [
        .refresh,
        .replyAll,
        .forward,
        .read,
        .flag,
        .createTask,
        .followUp,
        .move,
        .mailContext,
    ]
}

struct BrevMailNativeToolbarState: Equatable {
    var selectedHeader: MessageHeader?
    var hasSelectedFolder: Bool
    var canArchive: Bool
    var hasPresentedSheet = false
    var isRefreshing = false
    var isSwitchingMailbox = false
    var isPerformingCommandMutation = false
    var isComposeBlocked = false
    var isSettingsBlocked = false
    var canCreateTask = false
    var canFollowUp = false
    var canMove = false
    var usesExternalSettingsWindow = false
    var isMailContextPresented = false

    func isEnabled(_ item: BrevMailNativeToolbarItem) -> Bool {
        switch item {
        case .compose:
            return !isComposeBlocked
        case .settings:
            return !isSettingsBlocked
                && (usesExternalSettingsWindow || !hasPresentedSheet)
        case .mailContext:
            return true
        case .more:
            return BrevMailNativeToolbarItem.moreMenuItems.contains { isEnabled($0) }
        case .refresh:
            return hasSelectedFolder
                && !hasPresentedSheet
                && !isRefreshing
                && !isSwitchingMailbox
                && !isPerformingCommandMutation
        case .reply, .replyAll, .forward:
            return selectedHeader != nil && !isComposeBlocked
        case .read, .flag, .delete:
            return selectedHeader != nil
                && !hasPresentedSheet
                && !isRefreshing
                && !isSwitchingMailbox
                && !isPerformingCommandMutation
        case .archive:
            return selectedHeader != nil
                && canArchive
                && !hasPresentedSheet
                && !isRefreshing
                && !isSwitchingMailbox
                && !isPerformingCommandMutation
        case .createTask:
            return selectedHeader != nil && canCreateTask
        case .followUp:
            return selectedHeader != nil && canFollowUp
        case .move:
            return selectedHeader != nil && canMove
        }
    }

    func canInvoke(_ item: BrevMailNativeToolbarItem) -> Bool {
        isEnabled(item)
    }

    func messageHeaderForInvocation(_ item: BrevMailNativeToolbarItem) -> MessageHeader? {
        switch item {
        case .reply, .replyAll, .forward, .read, .flag, .archive, .delete, .createTask, .followUp, .move:
            guard canInvoke(item) else { return nil }
            return selectedHeader
        case .compose, .refresh, .settings, .mailContext, .more:
            return nil
        }
    }

    func label(for item: BrevMailNativeToolbarItem) -> String {
        switch item {
        case .read:
            guard let selectedHeader else { return item.label }
            return MessageCommandPresentation.readToggleTitle(for: selectedHeader)
        case .flag:
            guard let selectedHeader else { return item.label }
            return MessageCommandPresentation.flagToggleTitle(for: selectedHeader)
        case .mailContext:
            return isMailContextPresented ? "Hide AI Sidebar" : MailContextColumnVisibility.toolbarLabel
        case .compose, .refresh, .reply, .replyAll, .forward, .archive, .delete,
             .createTask, .followUp, .move, .settings, .more:
            return item.label
        }
    }

    func symbolName(for item: BrevMailNativeToolbarItem) -> String {
        switch item {
        case .compose:
            return "square.and.pencil"
        case .refresh:
            return "arrow.clockwise"
        case .reply:
            return "arrowshape.turn.up.left"
        case .replyAll:
            return "arrowshape.turn.up.left.2"
        case .forward:
            return "arrowshape.turn.up.right"
        case .read:
            return selectedHeader?.isRead == true ? "envelope.badge" : "envelope.open"
        case .flag:
            guard let selectedHeader else { return "flag" }
            return MessageCommandPresentation.flagToggleSymbolName(for: selectedHeader)
        case .archive:
            return "archivebox"
        case .delete:
            return "trash"
        case .createTask:
            return "checklist"
        case .followUp:
            return "flag"
        case .move:
            return "folder"
        case .mailContext:
            return MailContextColumnVisibility.toolbarSymbolName
        case .settings:
            return "gearshape"
        case .more:
            return "ellipsis.circle"
        }
    }
}

struct BrevMailNativeToolbarActions {
    var compose: @MainActor () -> Void
    var refresh: @MainActor () async -> Void
    var reply: @MainActor (MessageHeader) -> Void
    var replyAll: @MainActor (MessageHeader) -> Void
    var forward: @MainActor (MessageHeader) -> Void
    var toggleRead: @MainActor (MessageHeader) async -> Void
    var toggleStar: @MainActor (MessageHeader) async -> Void
    var archive: @MainActor (MessageHeader) async -> Void
    var delete: @MainActor (MessageHeader) async -> Void
    var createTask: @MainActor (MessageHeader) -> Void = { _ in }
    var followUp: @MainActor (MessageHeader) -> Void = { _ in }
    var move: @MainActor (MessageHeader) -> Void = { _ in }
    var settings: @MainActor () -> Void
    var toggleMailContext: @MainActor () -> Void
}

struct BrevMailNativeToolbarBridge: NSViewRepresentable {
    var state: BrevMailNativeToolbarState
    var actions: BrevMailNativeToolbarActions

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, actions: actions)
    }

    func makeNSView(context: Context) -> ToolbarAnchorView {
        let view = ToolbarAnchorView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ view: ToolbarAnchorView, context: Context) {
        view.coordinator = context.coordinator
        context.coordinator.update(state: state, actions: actions)
        context.coordinator.attach(to: view.window)

        DispatchQueue.main.async { [weak view, weak coordinator = context.coordinator] in
            coordinator?.attach(to: view?.window)
        }
    }

    static func dismantleNSView(_ view: ToolbarAnchorView, coordinator: Coordinator) {
        coordinator.detach(from: view.window)
    }

    /// Returns the index immediately after SwiftUI's native Search toolbar item.
    static func desiredMailContextIndex(in items: [NSToolbarItem]) -> Int? {
        guard let searchIndex = items.firstIndex(where: { $0 is NSSearchToolbarItem }) else {
            return nil
        }
        return searchIndex + 1
    }

    final class ToolbarAnchorView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.attach(to: window)
        }
    }

    final class Coordinator: NSObject, NSToolbarDelegate, NSToolbarItemValidation, NSMenuItemValidation {
        private var state: BrevMailNativeToolbarState
        private var actions: BrevMailNativeToolbarActions
        private weak var window: NSWindow?
        private var appliedMailContextState: Bool?

        init(
            state: BrevMailNativeToolbarState,
            actions: BrevMailNativeToolbarActions
        ) {
            self.state = state
            self.actions = actions
        }

        func update(
            state: BrevMailNativeToolbarState,
            actions: BrevMailNativeToolbarActions
        ) {
            let presentationChanged = self.state.isMailContextPresented != state.isMailContextPresented
            self.state = state
            self.actions = actions
            updateVisibleItems()

            guard presentationChanged,
                  appliedMailContextState != state.isMailContextPresented
            else {
                return
            }
            applyExternalMailContextChange(isPresented: state.isMailContextPresented)
        }

        func attach(to window: NSWindow?) {
            guard let window else { return }
            self.window = window

            if window.toolbar?.identifier != .brevMail {
                let toolbar = NSToolbar(identifier: .brevMail)
                toolbar.allowsUserCustomization = true
                toolbar.autosavesConfiguration = true
                toolbar.delegate = self
                toolbar.displayMode = .iconOnly
                toolbar.sizeMode = .regular
                toolbar.showsBaselineSeparator = false
                window.toolbar = toolbar
                window.toolbarStyle = .unified
            }
            window.toolbar?.showsBaselineSeparator = false
            BrevWindowChromeApplier.applyCurrentPreferences(to: window, for: .mainWindow)

            placeMailContextAfterSearch()
            if appliedMailContextState == nil {
                appliedMailContextState = state.isMailContextPresented
            }
            updateVisibleItems()
        }

        func detach(from window: NSWindow?) {
            guard window?.toolbar?.identifier == .brevMail else { return }
            window?.toolbar = nil
            self.window = nil
        }

        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            [
                .brevCompose,
                .brevRefresh,
                .flexibleSpace,
                .brevReply,
                .brevReplyAll,
                .brevForward,
                .brevRead,
                .brevFlag,
                .brevArchive,
                .brevDelete,
                .brevCreateTask,
                .brevFollowUp,
                .brevMove,
                .brevMailContext,
                .brevSettings,
                .brevMore
            ]
        }

        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            [
                .brevCompose,
                .flexibleSpace,
                .brevReply,
                .brevArchive,
                .brevDelete,
                .brevMore,
            ]
        }

        func toolbar(
            _ toolbar: NSToolbar,
            itemForItemIdentifier identifier: NSToolbarItem.Identifier,
            willBeInsertedIntoToolbar flag: Bool
        ) -> NSToolbarItem? {
            guard let toolbarItem = BrevMailNativeToolbarItem(identifier: identifier) else {
                return nil
            }

            let item: NSToolbarItem
            if toolbarItem == .more {
                let menuItem = NSMenuToolbarItem(itemIdentifier: identifier)
                menuItem.menu = makeMoreMenu()
                menuItem.showsIndicator = true
                item = menuItem
            } else {
                item = NSToolbarItem(itemIdentifier: identifier)
                item.target = self
                item.action = selector(for: toolbarItem)
            }
            // Without an explicit border the item renders as a bare image well
            // rather than a standard toolbar control, which is what drove the
            // SwiftUI-hosted workaround in #367.
            item.isBordered = true
            update(item, as: toolbarItem)
            return item
        }

        func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
            guard let toolbarItem = BrevMailNativeToolbarItem(identifier: item.itemIdentifier) else {
                return true
            }
            return state.isEnabled(toolbarItem)
        }

        func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
            guard let toolbarItem = menuItem.representedObject as? BrevMailNativeToolbarItem else {
                return true
            }
            return state.isEnabled(toolbarItem)
        }

        func toolbarWillAddItem(_ notification: Notification) {
            DispatchQueue.main.async { [weak self] in
                self?.placeMailContextAfterSearch()
            }
        }

        @objc private func compose() {
            guard state.canInvoke(.compose) else { return }
            Task { @MainActor in
                actions.compose()
            }
        }

        @objc private func refresh() {
            guard state.canInvoke(.refresh) else { return }
            Task { @MainActor in
                await actions.refresh()
            }
        }

        @objc private func reply() {
            guard let header = state.messageHeaderForInvocation(.reply) else { return }
            Task { @MainActor in
                actions.reply(header)
            }
        }

        @objc private func replyAll() {
            guard let header = state.messageHeaderForInvocation(.replyAll) else { return }
            Task { @MainActor in
                actions.replyAll(header)
            }
        }

        @objc private func forward() {
            guard let header = state.messageHeaderForInvocation(.forward) else { return }
            Task { @MainActor in
                actions.forward(header)
            }
        }

        @objc private func toggleRead() {
            guard let header = state.messageHeaderForInvocation(.read) else { return }
            Task { @MainActor in
                await actions.toggleRead(header)
            }
        }

        @objc private func toggleFlag() {
            guard let header = state.messageHeaderForInvocation(.flag) else { return }
            Task { @MainActor in
                await actions.toggleStar(header)
            }
        }

        @objc private func archive() {
            guard let header = state.messageHeaderForInvocation(.archive) else { return }
            Task { @MainActor in
                await actions.archive(header)
            }
        }

        @objc private func delete() {
            guard let header = state.messageHeaderForInvocation(.delete) else { return }
            Task { @MainActor in
                await actions.delete(header)
            }
        }

        @objc private func createTask() {
            guard let header = state.messageHeaderForInvocation(.createTask) else { return }
            Task { @MainActor in
                actions.createTask(header)
            }
        }

        @objc private func followUp() {
            guard let header = state.messageHeaderForInvocation(.followUp) else { return }
            Task { @MainActor in
                actions.followUp(header)
            }
        }

        @objc private func move() {
            guard let header = state.messageHeaderForInvocation(.move) else { return }
            Task { @MainActor in
                actions.move(header)
            }
        }

        @objc private func settings() {
            guard state.canInvoke(.settings) else { return }
            Task { @MainActor in
                actions.settings()
            }
        }

        // Opening and closing the AI Sidebar leaves the window frame alone. It
        // used to grow the window by the column's width and shrink it back on
        // close, which moved a window the user had sized and placed themselves
        // every time they toggled a pane. macOS sidebars and inspectors take
        // their width from the panes beside them; the reader gives up the space.
        @objc private func toggleMailContext() {
            guard state.canInvoke(.mailContext) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                state.isMailContextPresented.toggle()
                appliedMailContextState = state.isMailContextPresented
                updateVisibleItems()
                actions.toggleMailContext()
            }
        }

        private func placeMailContextAfterSearch() {
            guard let toolbar = window?.toolbar,
                  let desiredIndex = BrevMailNativeToolbarBridge.desiredMailContextIndex(in: toolbar.items)
            else {
                return
            }

            guard let currentIndex = toolbar.items.firstIndex(where: {
                $0.itemIdentifier == BrevMailNativeToolbarItem.mailContext.identifier
            }) else {
                return
            }
            guard currentIndex != desiredIndex else { return }

            toolbar.removeItem(at: currentIndex)
            let adjustedIndex = currentIndex < desiredIndex ? desiredIndex - 1 : desiredIndex
            toolbar.insertItem(
                withItemIdentifier: BrevMailNativeToolbarItem.mailContext.identifier,
                at: min(adjustedIndex, toolbar.items.count)
            )
        }

        private func applyExternalMailContextChange(isPresented: Bool) {
            appliedMailContextState = isPresented
        }

        private func updateVisibleItems() {
            window?.toolbar?.visibleItems?.forEach { item in
                guard let toolbarItem = BrevMailNativeToolbarItem(identifier: item.itemIdentifier) else {
                    return
                }
                update(item, as: toolbarItem)
            }
            window?.toolbar?.validateVisibleItems()
        }

        private func update(_ item: NSToolbarItem, as toolbarItem: BrevMailNativeToolbarItem) {
            let label = state.label(for: toolbarItem)
            item.label = label
            item.paletteLabel = label
            item.toolTip = label
            // Pin every glyph to one optical size so mixed symbol shapes
            // (sparkles, envelopes, arrows) share a footprint across the toolbar.
            item.image = NSImage(
                systemSymbolName: state.symbolName(for: toolbarItem),
                accessibilityDescription: label
            )?.withSymbolConfiguration(Self.symbolConfiguration)
            if let menuItem = item as? NSMenuToolbarItem {
                menuItem.menu = makeMoreMenu()
            }
        }

        private func makeMoreMenu() -> NSMenu {
            let menu = NSMenu(title: BrevMailNativeToolbarItem.more.label)
            for toolbarItem in BrevMailNativeToolbarItem.moreMenuItems {
                if toolbarItem == .replyAll || toolbarItem == .createTask || toolbarItem == .mailContext {
                    menu.addItem(.separator())
                }
                let item = NSMenuItem(
                    title: state.label(for: toolbarItem),
                    action: selector(for: toolbarItem),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = toolbarItem
                item.image = NSImage(
                    systemSymbolName: state.symbolName(for: toolbarItem),
                    accessibilityDescription: state.label(for: toolbarItem)
                )
                menu.addItem(item)
            }
            return menu
        }

        /// Shared optical size for toolbar glyphs, matching the system's default
        /// toolbar icon metrics.
        private static let symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 15,
            weight: .regular
        )

        private func selector(for item: BrevMailNativeToolbarItem) -> Selector {
            switch item {
            case .compose:
                return #selector(compose)
            case .refresh:
                return #selector(refresh)
            case .reply:
                return #selector(reply)
            case .replyAll:
                return #selector(replyAll)
            case .forward:
                return #selector(forward)
            case .read:
                return #selector(toggleRead)
            case .flag:
                return #selector(toggleFlag)
            case .archive:
                return #selector(archive)
            case .delete:
                return #selector(delete)
            case .createTask:
                return #selector(createTask)
            case .followUp:
                return #selector(followUp)
            case .move:
                return #selector(move)
            case .mailContext:
                return #selector(toggleMailContext)
            case .settings:
                return #selector(settings)
            case .more:
                return #selector(compose)
            }
        }
    }
}

private extension BrevMailNativeToolbarItem {
    init?(identifier: NSToolbarItem.Identifier) {
        guard let item = Self.allCases.first(where: { $0.identifier == identifier }) else {
            return nil
        }
        self = item
    }
}

private extension NSToolbar.Identifier {
    static let brevMail = NSToolbar.Identifier("app.brev.mail")
}

private extension NSToolbarItem.Identifier {
    static let brevCompose = NSToolbarItem.Identifier("app.brev.mail.compose")
    static let brevRefresh = NSToolbarItem.Identifier("app.brev.mail.refresh")
    static let brevReply = NSToolbarItem.Identifier("app.brev.mail.reply")
    static let brevReplyAll = NSToolbarItem.Identifier("app.brev.mail.replyAll")
    static let brevForward = NSToolbarItem.Identifier("app.brev.mail.forward")
    static let brevRead = NSToolbarItem.Identifier("app.brev.mail.read")
    static let brevFlag = NSToolbarItem.Identifier("app.brev.mail.flag")
    static let brevArchive = NSToolbarItem.Identifier("app.brev.mail.archive")
    static let brevDelete = NSToolbarItem.Identifier("app.brev.mail.delete")
    static let brevCreateTask = NSToolbarItem.Identifier("app.brev.mail.createTask")
    static let brevFollowUp = NSToolbarItem.Identifier("app.brev.mail.followUp")
    static let brevMove = NSToolbarItem.Identifier("app.brev.mail.move")
    static let brevMailContext = NSToolbarItem.Identifier("app.brev.mail.mailContext")
    static let brevSettings = NSToolbarItem.Identifier("app.brev.mail.settings")
    static let brevMore = NSToolbarItem.Identifier("app.brev.mail.more")
}
#endif
