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
import BrevDesign
import BrevThemes
import SwiftUI

#if os(macOS)
import AppKit

/// Trailing AI Sidebar inspector: sender facts above a mailbox chat shell.
struct MailContextColumn: View {
    @Environment(\.brevTheme) private var theme

    var selectedHeader: MessageHeader?
    var sourceID: MailSourceID?
    var backend: (any MailBackend)?
    var aiBackend: (any AIBackend)?
    var actionFolders: [Folder] = []
    var focusedFolder: Folder?
    var actionSourceScope: MailboxActionAgentSourceScope = .currentMailbox
    var executeAction: MailboxChatActionExecute?
    var folderNameByID: [String: String] = [:]
    var composeActions = MailComposePresentationActions(
        isBlocked: true,
        newMessage: {},
        reply: { _, _ in },
        replyAll: { _, _ in },
        forward: { _, _ in }
    )
    var onOpenMessage: (SenderContextRecentItem) -> Void = { _ in }
    var onShowAllFromSender: (String) -> Void = { _ in }
    var onOpenSettings: (() -> Void)?

    @State private var senderPanelState: SenderContextPanelState = .idle
    @State private var senderLoadGeneration = 0
    // Scene-scoped so each mail window retains its own AI Sidebar split.
    @SceneStorage("mail.context.senderPanelHeight")
    private var senderPanelHeight = Double(MailContextPanelSplitPolicy.defaultSenderHeight)
    @State private var liveSenderPanelHeight: CGFloat?
    @State private var panelResizeStartHeight: CGFloat?
    @State private var isPanelResizeHandleHovered = false
    @State private var isResizeCursorPushed = false
    private let senderContextCache = SenderContextSnapshotCache.shared

    var body: some View {
        // No title row. The column labelled itself "AI Sidebar" directly under a
        // toolbar button whose own label is "AI Sidebar", on a surface that is
        // visibly a sidebar — macOS inspectors do not title themselves. Dropping
        // it also takes the rule that had to sit under it, and gives the sender
        // block the top of the column.
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let availablePanelHeight = max(
                    0,
                    geometry.size.height - MailContextPanelSplitPolicy.resizeHandleHeight
                )
                let effectiveSenderPanelHeight = MailContextPanelSplitPolicy.senderHeight(
                    preferred: liveSenderPanelHeight ?? CGFloat(senderPanelHeight),
                    available: availablePanelHeight
                )

                VStack(spacing: 0) {
                    SenderContextPanel(
                        state: senderPanelState,
                        sourceID: sourceID,
                        composeActions: composeActions,
                        onOpenMessage: onOpenMessage,
                        onShowAllFromSender: onShowAllFromSender
                    )
                    .frame(height: effectiveSenderPanelHeight)

                    panelResizeHandle(availablePanelHeight: availablePanelHeight)

                    MailboxChatPanel(
                        scope: mailboxChatScope,
                        sourceID: sourceID,
                        aiBackend: aiBackend,
                        actionFolders: actionFolders,
                        focusedFolder: focusedFolder,
                        actionSourceScope: actionSourceScope,
                        executeAction: executeAction,
                        search: mailboxChatSearch,
                        onOpenCitation: { citation in
                            onOpenMessage(citation.recentItem)
                        },
                        onOpenSettings: onOpenSettings
                    )
                    .frame(maxHeight: .infinity)
                }
            }
        }
        // The sidebar material, not the content material the reader beside it
        // uses. Sharing the reader's surface left a hairline as the only thing
        // separating them, so the column read as part of the reader rather than
        // as a sidebar. This also pairs it with the folder sidebar on the
        // leading edge: both edges of the window are now sidebar, the middle is
        // content, which is how macOS inspectors read.
        .brevMailPaneSurface(.sidebar)
        .accessibilityLabel(MailContextColumnVisibility.toolbarLabel)
        .task(id: senderLoadTaskID) {
            await loadSenderContext()
        }
    }

    /// The split between the sender panel and the chat panel.
    ///
    /// At rest it is the same neutral hairline as every other separator in the
    /// column, running the full width the way an `NSSplitView` divider does. As
    /// a short accent-tinted capsule it read as a broken row separator rather
    /// than a control. The grabber only appears under the pointer, where it
    /// answers "can I drag this?" without competing at rest.
    private func panelResizeHandle(availablePanelHeight: CGFloat) -> some View {
        ZStack {
            MailContextDivider()

            if isPanelResizeHandleHovered {
                Capsule()
                    .fill(theme.accent.color.opacity(0.62))
                    .frame(
                        width: MailContextPanelSplitPolicy.resizeHandleWidth,
                        height: 3
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: MailContextPanelSplitPolicy.resizeHandleHeight)
        .contentShape(Rectangle())
        .onHover { isHovering in
            isPanelResizeHandleHovered = isHovering
            guard isResizeCursorPushed != isHovering else { return }
            isResizeCursorPushed = isHovering
            if isHovering {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            guard isResizeCursorPushed else { return }
            NSCursor.pop()
            isResizeCursorPushed = false
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let startHeight = panelResizeStartHeight
                        ?? MailContextPanelSplitPolicy.dragStartHeight(
                            preferred: CGFloat(senderPanelHeight),
                            available: availablePanelHeight
                        )
                    panelResizeStartHeight = startHeight
                    liveSenderPanelHeight = MailContextPanelSplitPolicy.senderHeight(
                        preferred: startHeight + value.translation.height,
                        available: availablePanelHeight
                    )
                }
                .onEnded { _ in
                    if let liveSenderPanelHeight {
                        senderPanelHeight = Double(liveSenderPanelHeight)
                    }
                    liveSenderPanelHeight = nil
                    panelResizeStartHeight = nil
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Resize AI Sidebar panels", bundle: .module))
        .accessibilityHint(String(localized: "Drag up or down to resize sender context and mailbox chat.", bundle: .module))
        .accessibilityAdjustableAction { direction in
            let adjustment: CGFloat
            switch direction {
            case .increment:
                adjustment = MailContextPanelSplitPolicy.keyboardAdjustment
            case .decrement:
                adjustment = -MailContextPanelSplitPolicy.keyboardAdjustment
            @unknown default:
                adjustment = 0
            }
            senderPanelHeight = Double(
                MailContextPanelSplitPolicy.senderHeight(
                    preferred: CGFloat(senderPanelHeight) + adjustment,
                    available: availablePanelHeight
                )
            )
            liveSenderPanelHeight = nil
        }
    }

    private var senderLoadTaskID: String {
        [
            selectedHeader?.id ?? "none",
            sourceID?.accountID ?? "no-account",
            sourceID?.mailboxID ?? "no-mailbox",
        ]
        .joined(separator: "|")
    }

    private var mailboxChatScope: MailboxChatScope {
        MailContextColumnScopePolicy.chatScope(
            selectedHeader: selectedHeader,
            focusedFolder: focusedFolder
        )
    }

    private var mailboxChatSearch: MailboxChatSearch {
        { query, sourceID in
            guard let backend else {
                throw MailBackendError.notConnected
            }
            if let sourceID {
                return try await backend.search(query, sourceID: sourceID)
            }
            return try await backend.search(query)
        }
    }

    @MainActor
    private func loadSenderContext() async {
        guard let selectedHeader else {
            senderPanelState = .idle
            return
        }
        guard let backend else {
            senderPanelState = .failed(selectedHeader, "No backend is available for the current selection.")
            return
        }

        let cacheSourceID = sourceID ?? MailSourceID(
            accountID: backend.account.id,
            mailboxID: backend.account.id
        )
        let cacheKey = SenderContextCacheKey(
            sourceID: cacheSourceID,
            senderEmail: selectedHeader.from.email
        )
        if let cached = await senderContextCache.value(for: cacheKey) {
            senderPanelState = .loaded(
                selectedHeader,
                cached.replacingSelectedIdentity(selectedHeader)
            )
            return
        }

        senderLoadGeneration += 1
        let generation = senderLoadGeneration
        senderPanelState = .loading(selectedHeader)

        do {
            try await Task.sleep(nanoseconds: MailContextSenderLoadPolicy.debounceNanoseconds)
            try Task.checkCancellation()
        } catch {
            return
        }

        let loader = SenderContextLoader(folderNameByID: folderNameByID)
        let loadTask = Task.detached(priority: .utility) {
            await loader.load(
                selected: selectedHeader,
                sourceID: sourceID,
                backend: backend
            )
        }
        let result = await withTaskCancellationHandler {
            await loadTask.value
        } onCancel: {
            loadTask.cancel()
        }

        guard !Task.isCancelled, generation == senderLoadGeneration else { return }

        if case .success(let snapshot) = result {
            await senderContextCache.insert(snapshot, for: cacheKey)
        }

        senderPanelState = SenderContextPanelStatePolicy.state(
            for: selectedHeader,
            result: result
        )
    }
}

/// Sizing rules for the vertically resizable panes in the AI Sidebar.
enum MailContextPanelSplitPolicy {
    static let defaultSenderHeight: CGFloat = 240
    static let senderMinimumHeight: CGFloat = 180
    static let chatMinimumHeight: CGFloat = 220
    static let resizeHandleHeight: CGFloat = 10
    static let resizeHandleWidth: CGFloat = 32
    static let keyboardAdjustment: CGFloat = 40

    static func senderHeight(preferred: CGFloat, available: CGFloat) -> CGFloat {
        let available = max(available, 0)
        guard available >= senderMinimumHeight + chatMinimumHeight else {
            return available / 2
        }

        return min(
            max(preferred, senderMinimumHeight),
            available - chatMinimumHeight
        )
    }

    /// The displayed divider position used as the first drag sample.
    static func dragStartHeight(preferred: CGFloat, available: CGFloat) -> CGFloat {
        senderHeight(preferred: preferred, available: available)
    }
}

/// Sizing rules for the AI Sidebar's own width.
///
/// The column shipped at a fixed 320pt with no way to change it, while every
/// other column in the window is draggable. Its bounds are the same ones
/// `MailPaneColumnWidthPolicy.mailContext` already declares.
enum MailContextColumnWidthPolicy {
    static let resizeHandleWidth: CGFloat = 6
    static let grabberHeight: CGFloat = 32
    static let keyboardAdjustment: CGFloat = 40

    /// Clamps a preferred width to the column's declared bounds.
    static func width(preferred: CGFloat, bounds: MailPaneColumnWidth) -> CGFloat {
        min(max(preferred, bounds.minimum), bounds.maximum)
    }

    /// A drag on the leading edge widens the column as the pointer moves left,
    /// so the translation is subtracted rather than added.
    static func width(
        dragStartWidth: CGFloat,
        translation: CGFloat,
        bounds: MailPaneColumnWidth
    ) -> CGFloat {
        width(preferred: dragStartWidth - translation, bounds: bounds)
    }
}

/// The boundary between the reader and the AI Sidebar.
///
/// An explicit hairline in the theme's separator colour rather than SwiftUI's
/// `Divider()`. Inside an `HStack` that drew a washed-out vertical bar whose
/// weight did not match any other edge in the window, so the column read as a
/// strip pasted over the reader instead of a column of the window. The edge
/// carries the boundary together with the column's own sidebar material — the
/// material is what makes it legible as a sidebar; the hairline just resolves
/// it crisply.
struct MailContextColumnEdge: View {
    @Environment(\.brevTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.textPrimary.color.opacity(MailContextSeparator.edgeOpacity))
            .frame(width: 1)
            // Runs the full window height, through the toolbar, the way the
            // folder sidebar's edge does. The column's material already reaches
            // the top; the hairline stopped at the safe area, so the boundary
            // began below the toolbar and the column read as a panel dropped
            // into the reader rather than as a sidebar of the window.
            .ignoresSafeArea(.container, edges: .top)
            .accessibilityHidden(true)
    }
}

enum SenderContextPanelStatePolicy {
    static func state(
        for selectedHeader: MessageHeader,
        result: Result<SenderContextSnapshot, any Error>
    ) -> SenderContextPanelState {
        switch result {
        case .success(let snapshot):
            if (snapshot.messageCount ?? snapshot.recent.count) == 0 {
                return .empty(selectedHeader)
            }
            return .loaded(selectedHeader, snapshot)
        case .failure(let error):
            let message = error.localizedDescription.isEmpty ? "Unknown error" : error.localizedDescription
            return .failed(selectedHeader, message)
        }
    }
}

/// Applies the macOS AI Sidebar as an in-window trailing column.
struct MailContextInspectorModifier: ViewModifier {
    @Binding var isPresented: Bool
    let platform: MailPanePlatform
    let selectedHeader: MessageHeader?
    let sourceID: MailSourceID?
    let backend: (any MailBackend)?
    let aiBackend: (any AIBackend)?
    let actionFolders: [Folder]
    let focusedFolder: Folder?
    let actionSourceScope: MailboxActionAgentSourceScope
    let executeAction: MailboxChatActionExecute?
    let folderNameByID: [String: String]
    let composeActions: MailComposePresentationActions
    let onOpenMessage: (SenderContextRecentItem) -> Void
    let onShowAllFromSender: (String) -> Void
    var onOpenSettings: (() -> Void)?

    // Scene-scoped so each mail window keeps its own AI Sidebar width.
    @SceneStorage("mail.context.columnWidth")
    private var storedColumnWidth = Double(MailPaneColumnWidthPolicy.mailContextDefaultWidth)
    @State private var liveColumnWidth: CGFloat?
    @State private var columnResizeStartWidth: CGFloat?
    @State private var isColumnResizeHandleHovered = false
    @State private var isColumnResizeCursorPushed = false
    @Environment(\.brevTheme) private var theme

    // Freeze-and-reveal transition state. While the window animates its
    // width, the mail content is pinned at its pre-toggle width and the
    // column sits fully laid out after it, so the only thing that moves on
    // screen is the window edge sweeping across static content. Animating
    // the content alongside the window is not an option: the SwiftUI layout
    // clock and the AppKit window-animation clock tick out of phase, and the
    // per-frame width mismatch makes the whole content jitter horizontally
    // (measured at up to ±21pt with matched 0.25s ease-in-out curves).
    @State private var isColumnMounted = false
    @State private var frozenContentWidth: CGFloat?
    @State private var contentWidthMeasurement = MailContextContentWidthMeasurement()
    @State private var unfreezeTask: Task<Void, Never>?

    @ViewBuilder
    func body(content: Content) -> some View {
        let columnExecuteAction: MailboxChatActionExecute? = executeAction.map { executeAction in
            { @Sendable [executeAction] plan in
                try await executeAction(plan)
            }
        }

        if platform == .macOS, let width = MailPaneColumnWidthPolicy.mailContext(platform: platform) {
            let columnWidth = MailContextColumnWidthPolicy.width(
                preferred: liveColumnWidth ?? CGFloat(storedColumnWidth),
                bounds: width
            )

            HStack(spacing: 0) {
                content
                    // One flexible frame for both states so the content's view
                    // identity is stable across freeze/unfreeze. Frozen: an
                    // exact width. Unfrozen: greedy, as before.
                    .frame(
                        minWidth: frozenContentWidth,
                        idealWidth: frozenContentWidth,
                        maxWidth: frozenContentWidth ?? .infinity,
                        maxHeight: .infinity
                    )
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.width
                    } action: { newWidth in
                        contentWidthMeasurement.width = newWidth
                    }

                if isColumnMounted {
                    HStack(spacing: 0) {
                        columnResizeHandle(bounds: width, columnWidth: columnWidth)

                        MailContextColumn(
                            selectedHeader: selectedHeader,
                            sourceID: sourceID,
                            backend: backend,
                            aiBackend: aiBackend,
                            actionFolders: actionFolders,
                            focusedFolder: focusedFolder,
                            actionSourceScope: actionSourceScope,
                            executeAction: columnExecuteAction,
                            folderNameByID: folderNameByID,
                            composeActions: composeActions,
                            onOpenMessage: onOpenMessage,
                            onShowAllFromSender: onShowAllFromSender,
                            onOpenSettings: onOpenSettings
                        )
                        .frame(width: columnWidth)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .zIndex(1)
                    // Invisible in the normal path (the removal happens while
                    // the column is entirely beyond the window edge); a slide
                    // when the window could not resize, so the column still
                    // leaves gracefully instead of popping.
                    .transition(.move(edge: .trailing))
                }
            }
            // Leading-pinned, and while frozen the reported minimum width is
            // zero so the overflowing (content + column) layout cannot force
            // the window frame — the window animator alone decides how much
            // of the column is revealed.
            .frame(
                minWidth: frozenContentWidth == nil ? nil : 0,
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .leading
            )
            .task {
                isColumnMounted = isPresented
            }
            .onChange(of: isPresented) { _, nowPresented in
                beginTransition(opening: nowPresented)
            }
            .background {
                MailContextWindowWidthAdjuster(
                    isPresented: isPresented,
                    columnWidth: columnWidth
                )
                .frame(width: 0, height: 0)
            }
        } else {
            content
        }
    }

    /// Starts the freeze-and-reveal transition for an open or close toggle.
    ///
    /// Opening: pin the content at its current width and mount the column
    /// after it in the same transaction, so the finished layout exists
    /// immediately and the animating window edge just reveals it. Closing:
    /// pin the content and leave the column mounted so the shrinking window
    /// conceals it, then unmount once the window has stopped moving.
    /// Unfreezing is wrapped in an animation that is a geometric no-op when
    /// the window resized fully, and smooths the residual reflow when it
    /// could not (already at screen width, or the user had shrunk it).
    private func beginTransition(opening: Bool) {
        unfreezeTask?.cancel()
        frozenContentWidth = contentWidthMeasurement.width
        if opening {
            isColumnMounted = true
        }
        unfreezeTask = Task { @MainActor in
            let settle = MailContextWindowGrowthPolicy.animationDuration + 0.05
            try? await Task.sleep(nanoseconds: UInt64(settle * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                isColumnMounted = isPresented
                frozenContentWidth = nil
            }
        }
    }

    /// The column's leading edge, as a drag handle.
    ///
    /// Same shape as the sender/chat splitter inside the column: the hairline is
    /// what you see at rest, and a grabber appears under the pointer to answer
    /// "can I drag this?" without competing when you are not.
    private func columnResizeHandle(bounds: MailPaneColumnWidth, columnWidth: CGFloat) -> some View {
        ZStack {
            MailContextColumnEdge()

            if isColumnResizeHandleHovered {
                Capsule()
                    .fill(theme.accent.color.opacity(0.62))
                    .frame(width: 3, height: MailContextColumnWidthPolicy.grabberHeight)
            }
        }
        .frame(maxHeight: .infinity)
        .frame(width: MailContextColumnWidthPolicy.resizeHandleWidth)
        .contentShape(Rectangle())
        .onHover { isHovering in
            isColumnResizeHandleHovered = isHovering
            guard isColumnResizeCursorPushed != isHovering else { return }
            isColumnResizeCursorPushed = isHovering
            if isHovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            guard isColumnResizeCursorPushed else { return }
            NSCursor.pop()
            isColumnResizeCursorPushed = false
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let startWidth = columnResizeStartWidth ?? columnWidth
                    columnResizeStartWidth = startWidth
                    liveColumnWidth = MailContextColumnWidthPolicy.width(
                        dragStartWidth: startWidth,
                        translation: value.translation.width,
                        bounds: bounds
                    )
                }
                .onEnded { _ in
                    if let liveColumnWidth {
                        storedColumnWidth = Double(liveColumnWidth)
                    }
                    liveColumnWidth = nil
                    columnResizeStartWidth = nil
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Resize AI Sidebar", bundle: .module))
        .accessibilityHint(String(localized: "Drag left or right to resize the AI Sidebar.", bundle: .module))
        .accessibilityAdjustableAction { direction in
            let adjustment: CGFloat = switch direction {
            case .increment: MailContextColumnWidthPolicy.keyboardAdjustment
            case .decrement: -MailContextColumnWidthPolicy.keyboardAdjustment
            @unknown default: 0
            }
            storedColumnWidth = Double(
                MailContextColumnWidthPolicy.width(
                    preferred: columnWidth + adjustment,
                    bounds: bounds
                )
            )
            liveColumnWidth = nil
        }
    }
}

/// Retains the latest geometry sample without invalidating the SwiftUI tree.
/// The value is read only when an AI Sidebar open/close transition begins.
@MainActor
private final class MailContextContentWidthMeasurement {
    var width: CGFloat = 0
}
#endif
