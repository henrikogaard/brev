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
import SwiftUI

/// Async action published by the root mail view for commands that
/// need to refresh the selected folder through root-owned state.
public struct MailRefreshAction {
    public let isRefreshing: Bool
    public let isBlocked: Bool

    public var isAvailable: Bool {
        !isRefreshing && !isBlocked
    }

    private let action: @MainActor () async -> Void

    public init(
        isRefreshing: Bool = false,
        isBlocked: Bool = false,
        _ action: @escaping @MainActor () async -> Void
    ) {
        self.isRefreshing = isRefreshing
        self.isBlocked = isBlocked
        self.action = action
    }

    @MainActor
    public func callAsFunction() async {
        guard isAvailable else { return }
        await action()
    }
}

/// Async message mutations published by the root mail view so macOS
/// menu commands share toolbar-side refresh and folder-count behavior.
public struct MailMessageCommandActions {
    public let isPerformingMutation: Bool
    public let isBlocked: Bool

    public var isAvailable: Bool {
        !isPerformingMutation && !isBlocked
    }

    private let toggleReadAction: @MainActor (MessageHeader) async -> Void
    private let toggleStarAction: @MainActor (MessageHeader) async -> Void
    private let archiveAction: @MainActor (MessageHeader) async -> Void
    private let moveAction: @MainActor (MessageHeader, Folder) async -> Void
    private let setJunkAction: @MainActor (MessageHeader, Bool) async -> Void
    private let deleteAction: @MainActor (MessageHeader) async -> Void

    public init(
        isPerformingMutation: Bool = false,
        isBlocked: Bool = false,
        toggleRead: @escaping @MainActor (MessageHeader) async -> Void,
        toggleStar: @escaping @MainActor (MessageHeader) async -> Void,
        archive: @escaping @MainActor (MessageHeader) async -> Void,
        move: @escaping @MainActor (MessageHeader, Folder) async -> Void,
        setJunk: @escaping @MainActor (MessageHeader, Bool) async -> Void,
        delete: @escaping @MainActor (MessageHeader) async -> Void
    ) {
        self.isPerformingMutation = isPerformingMutation
        self.isBlocked = isBlocked
        toggleReadAction = toggleRead
        toggleStarAction = toggleStar
        archiveAction = archive
        moveAction = move
        setJunkAction = setJunk
        deleteAction = delete
    }

    @MainActor
    public func toggleRead(_ header: MessageHeader) async {
        guard isAvailable else { return }
        await toggleReadAction(header)
    }

    @MainActor
    public func toggleStar(_ header: MessageHeader) async {
        guard isAvailable else { return }
        await toggleStarAction(header)
    }

    @MainActor
    public func archive(_ header: MessageHeader) async {
        guard isAvailable else { return }
        await archiveAction(header)
    }

    @MainActor
    public func move(_ header: MessageHeader, to folder: Folder) async {
        guard isAvailable else { return }
        await moveAction(header, folder)
    }

    @MainActor
    public func setJunk(_ isJunk: Bool, for header: MessageHeader) async {
        guard isAvailable else { return }
        await setJunkAction(header, isJunk)
    }

    @MainActor
    public func delete(_ header: MessageHeader) async {
        guard isAvailable else { return }
        await deleteAction(header)
    }
}

/// Pure command-state projection for macOS menu and keyboard actions.
/// Keeping this outside SwiftUI command builders makes shortcut
/// enablement testable without a live backend or UI automation.
public struct MailMessageCommandState: Equatable, Sendable {
    public let readToggleTitle: String
    public let flagToggleTitle: String
    public let canReply: Bool
    public let canReplyAll: Bool
    public let canForward: Bool
    public let canToggleRead: Bool
    public let canToggleFlag: Bool
    public let canArchive: Bool
    public let canMove: Bool
    public let junkActionTitle: String?
    public let canSetJunk: Bool
    public let canDelete: Bool
}

public enum MailMessageCommandStatePolicy {
    public static func state(
        selectedHeader: MessageHeader?,
        folders: [Folder]?,
        backendCapabilities: BackendCapabilities = [],
        messageActionsAvailable: Bool,
        composePresentationAvailable: Bool
    ) -> MailMessageCommandState {
        let hasSelection = selectedHeader != nil
        let hasArchiveFolder = folders?.contains { $0.role == .archive } == true
        let currentFolder = folders?.first { $0.id == selectedHeader?.folderID }
        let junkActionTitle = selectedHeader.map { _ in
            MessageCommandPresentation.junkActionTitle(
                currentFolder: currentFolder,
                capabilities: backendCapabilities,
                folders: folders ?? []
            )
        } ?? nil
        let canMove = selectedHeader.map { header in
            MessageCommandPresentation.moveFolderCandidates(
                from: folders ?? [],
                currentFolderID: header.folderID
            ).isEmpty == false
        } ?? false

        return MailMessageCommandState(
            readToggleTitle: selectedHeader.map(MessageCommandPresentation.readToggleTitle) ?? "Mark as Read",
            flagToggleTitle: selectedHeader.map(MessageCommandPresentation.flagToggleTitle) ?? "Flag",
            canReply: hasSelection && composePresentationAvailable,
            canReplyAll: hasSelection && composePresentationAvailable,
            canForward: hasSelection && composePresentationAvailable,
            canToggleRead: hasSelection && messageActionsAvailable,
            canToggleFlag: hasSelection && messageActionsAvailable,
            canArchive: hasSelection && messageActionsAvailable && hasArchiveFolder,
            canMove: hasSelection && messageActionsAvailable && canMove,
            junkActionTitle: junkActionTitle,
            canSetJunk: hasSelection && messageActionsAvailable && junkActionTitle != nil,
            canDelete: hasSelection && messageActionsAvailable
        )
    }
}

/// Async compose presentation actions published by the root mail view
/// so toolbars and menu commands share root-owned blocking policy.
public struct MailComposePresentationActions {
    public let isBlocked: Bool

    public var isAvailable: Bool {
        !isBlocked
    }

    private let newMessageAction: @MainActor () -> Void
    private let replyAction: @MainActor (MessageHeader, MailSourceID?) -> Void
    private let replyAllAction: @MainActor (MessageHeader, MailSourceID?) -> Void
    private let forwardAction: @MainActor (MessageHeader, MailSourceID?) -> Void

    public init(
        isBlocked: Bool = false,
        newMessage: @escaping @MainActor () -> Void,
        reply: @escaping @MainActor (MessageHeader) -> Void,
        replyAll: @escaping @MainActor (MessageHeader) -> Void,
        forward: @escaping @MainActor (MessageHeader) -> Void
    ) {
        self.isBlocked = isBlocked
        newMessageAction = newMessage
        replyAction = { header, _ in reply(header) }
        replyAllAction = { header, _ in replyAll(header) }
        forwardAction = { header, _ in forward(header) }
    }

    public init(
        isBlocked: Bool = false,
        newMessage: @escaping @MainActor () -> Void,
        reply: @escaping @MainActor (MessageHeader, MailSourceID?) -> Void,
        replyAll: @escaping @MainActor (MessageHeader, MailSourceID?) -> Void,
        forward: @escaping @MainActor (MessageHeader, MailSourceID?) -> Void
    ) {
        self.isBlocked = isBlocked
        newMessageAction = newMessage
        replyAction = reply
        replyAllAction = replyAll
        forwardAction = forward
    }

    @MainActor
    public func newMessage() {
        guard isAvailable else { return }
        newMessageAction()
    }

    @MainActor
    public func reply(_ header: MessageHeader, sourceID: MailSourceID? = nil) {
        guard isAvailable else { return }
        replyAction(header, sourceID)
    }

    @MainActor
    public func replyAll(_ header: MessageHeader, sourceID: MailSourceID? = nil) {
        guard isAvailable else { return }
        replyAllAction(header, sourceID)
    }

    @MainActor
    public func forward(_ header: MessageHeader, sourceID: MailSourceID? = nil) {
        guard isAvailable else { return }
        forwardAction(header, sourceID)
    }
}

/// Root-owned presentation action for the supervised mailbox assistant.
/// The assistant itself stays in the mail root so it can use the
/// current source, folder list, search path, and mutation policy.
public struct MailMailboxActionAgentActions {
    public let isVisible: Bool
    public let isBlocked: Bool

    public var isAvailable: Bool {
        isVisible && !isBlocked
    }

    private let presentAction: @MainActor () -> Void

    public init(
        isVisible: Bool = true,
        isBlocked: Bool = false,
        present: @escaping @MainActor () -> Void
    ) {
        self.isVisible = isVisible
        self.isBlocked = isBlocked
        presentAction = present
    }

    @MainActor
    public func present() {
        guard isAvailable else { return }
        presentAction()
    }
}

/// Mail import source format selected by a platform file picker.
public enum MailImportSourceFormat: String, Equatable, Sendable {
    case mbox
    case eml
    case maildir
}

/// Request passed from platform command surfaces into the root mail view.
public struct MailImportRequest: Equatable, Sendable {
    public let url: URL
    public let format: MailImportSourceFormat

    public init(url: URL, format: MailImportSourceFormat) {
        self.url = url
        self.format = format
    }
}

/// Import action published by the root mail view so the macOS
/// `Import Mail…` menu command can hand a user-chosen source to
/// the view without needing AppKit imports inside BrevMail.
public struct MailImportAction {
    public let isBlocked: Bool

    public var isAvailable: Bool {
        !isBlocked
    }

    private let action: @MainActor (MailImportRequest) -> Void

    public init(
        isBlocked: Bool = false,
        _ action: @escaping @MainActor (MailImportRequest) -> Void
    ) {
        self.isBlocked = isBlocked
        self.action = action
    }

    @MainActor
    public func callAsFunction(_ request: MailImportRequest) {
        guard isAvailable else { return }
        action(request)
    }

    @MainActor
    public func callAsFunction(_ url: URL) {
        callAsFunction(MailImportRequest(url: url, format: .mbox))
    }
}

/// Source-owned folder export action handed to the native file picker.
public struct MailFolderExportAction {
    public let folderName: String
    public let sourceTitle: String
    public let isAvailable: Bool
    private let action: @MainActor (URL) -> Void

    /// Captures source details and availability before a save panel opens.
    public init(folderName: String, sourceTitle: String, isAvailable: Bool,
                action: @escaping @MainActor (URL) -> Void) {
        self.folderName = folderName
        self.sourceTitle = sourceTitle
        self.isAvailable = isAvailable
        self.action = action
    }

    /// Starts the captured export when the user chooses a destination.
    @MainActor
    public func callAsFunction(_ destination: URL) {
        guard isAvailable else { return }
        action(destination)
    }
}

private struct FocusedFolderExportKey: FocusedValueKey {
    typealias Value = MailFolderExportAction
}

/// Print/export actions published by the active message detail view so
/// macOS File-menu commands operate on the visible message.
public struct MailPrintExportActions {
    public let isAvailable: Bool

    private let printAction: @MainActor () -> Void
    private let exportPDFAction: @MainActor () -> Void

    public init(
        isAvailable: Bool = true,
        print: @escaping @MainActor () -> Void,
        exportPDF: @escaping @MainActor () -> Void
    ) {
        self.isAvailable = isAvailable
        printAction = print
        exportPDFAction = exportPDF
    }

    @MainActor
    public func print() {
        guard isAvailable else { return }
        printAction()
    }

    @MainActor
    public func exportPDF() {
        guard isAvailable else { return }
        exportPDFAction()
    }
}

// MARK: - Focused values

/// Key that publishes the active `MailNavigationState` so macOS
/// `.commands { }` can manipulate selection, present sheets, etc.
public struct FocusedNavigationKey: FocusedValueKey {
    public typealias Value = MailNavigationState
}

/// Key that publishes the active `MailBackend` so macOS commands
/// can perform backend operations (mark read, flag, move, delete).
public struct FocusedBackendKey: FocusedValueKey {
    public typealias Value = any MailBackend
}

/// Key that publishes the currently selected folder list so
/// commands can access archive/trash targets.
public struct FocusedFoldersKey: FocusedValueKey {
    public typealias Value = [Folder]
}

/// Key that publishes local folder aliases so macOS commands can label
/// destination menus the same way as the visible mailbox sidebar.
public struct FocusedFolderAliasPreferencesKey: FocusedValueKey {
    public typealias Value = FolderAliasPreferences
}

/// Key that publishes a root-owned selected-folder refresh action so
/// macOS menu commands stay in sync with toolbar refresh behavior.
public struct FocusedRefreshSelectedFolderKey: FocusedValueKey {
    public typealias Value = MailRefreshAction
}

/// Key that publishes root-owned message command actions for macOS
/// menu commands.
public struct FocusedMessageCommandActionsKey: FocusedValueKey {
    public typealias Value = MailMessageCommandActions
}

/// Key that publishes root-owned compose presentation actions so
/// commands cannot open compose while mailbox state is unstable.
public struct FocusedComposePresentationActionsKey: FocusedValueKey {
    public typealias Value = MailComposePresentationActions
}

/// Key that publishes root-owned mailbox assistant presentation
/// actions.
public struct FocusedMailboxActionAgentActionsKey: FocusedValueKey {
    public typealias Value = MailMailboxActionAgentActions
}

/// Key that publishes print/PDF actions for the current reading pane.
public struct FocusedPrintExportActionsKey: FocusedValueKey {
    public typealias Value = MailPrintExportActions
}

/// Key that publishes the root-owned import action so the macOS
/// `Import Mail…` command can pass a file URL into the view hierarchy
/// without AppKit leaking into the BrevMail package.
public struct FocusedImportMailKey: FocusedValueKey {
    public typealias Value = MailImportAction
}

/// Key that publishes the root-owned Mail Context toggle action so
/// macOS commands can register the shortcut without a hidden button.
struct FocusedMailContextColumnActionKey: FocusedValueKey {
    typealias Value = MailContextColumnAction
}

public extension FocusedValues {
    var mailNavigation: MailNavigationState? {
        get { self[FocusedNavigationKey.self] }
        set { self[FocusedNavigationKey.self] = newValue }
    }

    var mailBackend: (any MailBackend)? {
        get { self[FocusedBackendKey.self] }
        set { self[FocusedBackendKey.self] = newValue }
    }

    var mailFolders: [Folder]? {
        get { self[FocusedFoldersKey.self] }
        set { self[FocusedFoldersKey.self] = newValue }
    }

    var mailFolderAliasPreferences: FolderAliasPreferences? {
        get { self[FocusedFolderAliasPreferencesKey.self] }
        set { self[FocusedFolderAliasPreferencesKey.self] = newValue }
    }

    var refreshSelectedMailFolder: MailRefreshAction? {
        get { self[FocusedRefreshSelectedFolderKey.self] }
        set { self[FocusedRefreshSelectedFolderKey.self] = newValue }
    }

    var mailMessageCommandActions: MailMessageCommandActions? {
        get { self[FocusedMessageCommandActionsKey.self] }
        set { self[FocusedMessageCommandActionsKey.self] = newValue }
    }

    var mailComposePresentationActions: MailComposePresentationActions? {
        get { self[FocusedComposePresentationActionsKey.self] }
        set { self[FocusedComposePresentationActionsKey.self] = newValue }
    }

    var mailMailboxActionAgentActions: MailMailboxActionAgentActions? {
        get { self[FocusedMailboxActionAgentActionsKey.self] }
        set { self[FocusedMailboxActionAgentActionsKey.self] = newValue }
    }

    var mailPrintExportActions: MailPrintExportActions? {
        get { self[FocusedPrintExportActionsKey.self] }
        set { self[FocusedPrintExportActionsKey.self] = newValue }
    }

    /// Folder export for the focused mailbox workspace.
    var mailFolderExportAction: MailFolderExportAction? {
        get { self[FocusedFolderExportKey.self] }
        set { self[FocusedFolderExportKey.self] = newValue }
    }

    var mailImportAction: MailImportAction? {
        get { self[FocusedImportMailKey.self] }
        set { self[FocusedImportMailKey.self] = newValue }
    }

    internal var mailContextColumnAction: MailContextColumnAction? {
        get { self[FocusedMailContextColumnActionKey.self] }
        set { self[FocusedMailContextColumnActionKey.self] = newValue }
    }
}
