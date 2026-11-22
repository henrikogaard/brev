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
import BrevDesign
import BrevThemes
import SwiftUI

#if os(macOS)
import AppKit
#endif

/// Full-window sequential triage surface (#293): one conversation at a time
/// with no sidebar or list, a progress line, and single-key decision hints.
struct TriageView<ReaderContent: View>: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.undoQueue) private var undoQueue

    let session: TriageSession
    let canArchive: Bool
    let canSnooze: Bool
    let canReply: Bool
    let isKeyHandlingSuspended: Bool
    let onArchive: () -> Void
    let onSnooze: () -> Void
    let onReply: () -> Void
    let onSkip: () -> Void
    let onDone: () -> Void
    let onUndo: () -> Void
    let onPreloadNext: () -> Void
    @ViewBuilder let readerContent: (TriageItem, MessageBody?) -> ReaderContent

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if let errorMessage = session.errorMessage {
                BrevInlineStatus(message: errorMessage, tone: .danger)
                    .padding(.horizontal, BrevSpacing.lg)
                    .padding(.vertical, BrevSpacing.xs)
            }
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomBar
        }
        .background(theme.bgPrimary.color)
        .onAppear {
            onPreloadNext()
        }
        .onChange(of: session.currentItem?.id) { _, _ in
            onPreloadNext()
        }
        #if os(macOS)
        .background(
            TriageKeyMonitorBridge(
                isSuspended: isKeyHandlingSuspended || session.isPerformingAction,
                canArchive: canArchive && session.currentItem != nil,
                canSnooze: canSnooze && session.currentItem != nil,
                canReply: canReply && session.currentItem != nil,
                hasCurrentItem: session.currentItem != nil,
                onAction: handleKeyAction
            )
        )
        #endif
    }

    private var topBar: some View {
        HStack(spacing: BrevSpacing.md) {
            Text(verbatim: TriagePresentation.title(remainingCount: session.remainingCount, locale: locale))
                .brevFont(.headline)
                .foregroundStyle(theme.textPrimary.color)
                .monospacedDigit()
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("triage.title")
            Spacer()
            Button(action: onDone) {
                Text("Done", bundle: .module)
                    .brevFont(.callout)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("triage.topDone")
        }
        .padding(.horizontal, BrevSpacing.lg)
        .padding(.vertical, BrevSpacing.sm)
        .background(theme.bgSecondary.color)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BrevSeparator.color(for: theme))
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        if let item = session.currentItem {
            readerContent(item, session.preloadedBody(for: item.id))
                .id(item.id)
        } else {
            caughtUpView
        }
    }

    private var caughtUpView: some View {
        VStack(spacing: BrevSpacing.md) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(theme.accent.color)
                .accessibilityHidden(true)
            Text("All caught up", bundle: .module)
                .brevFont(.title)
                .foregroundStyle(theme.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
            Text("You reviewed every conversation in this queue.", bundle: .module)
                .brevFont(.body)
                .foregroundStyle(theme.textSecondary.color)
                .multilineTextAlignment(.center)
            HStack(spacing: BrevSpacing.sm) {
                if undoQueue?.canUndo == true {
                    Button(action: onUndo) {
                        Text("Undo", bundle: .module)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                Button(action: onDone) {
                    Text("Done", bundle: .module)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent.color)
                .controlSize(.large)
            }
            .padding(.top, BrevSpacing.xs)
        }
        .padding(BrevSpacing.xxl)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("triage.caughtUp")
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            progressLine
            HStack(spacing: BrevSpacing.sm) {
                if session.currentItem != nil {
                    actionButton(
                        key: "E",
                        title: String(localized: "Archive", bundle: .module),
                        systemImage: "archivebox",
                        isDisabled: !canArchive || session.isPerformingAction,
                        identifier: "triage.action.archive",
                        action: onArchive
                    )
                    if canSnooze {
                        actionButton(
                            key: "H",
                            title: String(localized: "Snooze until tomorrow", bundle: .module),
                            systemImage: "clock",
                            isDisabled: session.isPerformingAction,
                            identifier: "triage.action.snooze",
                            action: onSnooze
                        )
                    }
                    actionButton(
                        key: "R",
                        title: String(localized: "Reply", bundle: .module),
                        systemImage: "arrowshape.turn.up.left",
                        isDisabled: !canReply || session.isPerformingAction,
                        identifier: "triage.action.reply",
                        action: onReply
                    )
                    actionButton(
                        key: "J",
                        title: String(localized: "Skip", bundle: .module),
                        systemImage: "arrow.right",
                        isDisabled: session.isPerformingAction,
                        identifier: "triage.action.skip",
                        action: onSkip
                    )
                }
                Spacer(minLength: BrevSpacing.sm)
                actionButton(
                    key: String(localized: "esc", bundle: .module),
                    title: String(localized: "Done", bundle: .module),
                    systemImage: nil,
                    isDisabled: false,
                    identifier: "triage.action.done",
                    action: onDone
                )
            }
            .padding(.horizontal, BrevSpacing.lg)
            .padding(.vertical, BrevSpacing.sm)
        }
        .background(theme.bgSecondary.color)
    }

    private var progressLine: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(theme.bgTertiary.color)
                Rectangle()
                    .fill(theme.accent.color)
                    .frame(width: max(0, proxy.size.width * session.progress))
                    .animation(.easeOut(duration: 0.18), value: session.progress)
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }

    private func actionButton(
        key: String,
        title: String,
        systemImage: String?,
        isDisabled: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: BrevSpacing.xs) {
                Text(verbatim: key)
                    .brevFont(.caption)
                    .fontWeight(.semibold)
                    .monospaced()
                    .foregroundStyle(theme.textPrimary.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: BrevRadius.sm)
                            .fill(theme.bgTertiary.color)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: BrevRadius.sm)
                            .strokeBorder(theme.border.color, lineWidth: 0.5)
                    )
                if let systemImage {
                    Image(systemName: systemImage)
                        .brevFont(.caption)
                        .foregroundStyle(theme.textSecondary.color)
                        .accessibilityHidden(true)
                }
                Text(verbatim: title)
                    .brevFont(.callout)
                    .foregroundStyle(theme.textPrimary.color)
            }
            .padding(.horizontal, BrevSpacing.sm)
            .padding(.vertical, BrevSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .accessibilityIdentifier(identifier)
    }

    #if os(macOS)
    private func handleKeyAction(_ action: TriageKeyAction) {
        switch action {
        case .archive:
            guard canArchive, session.currentItem != nil else { return }
            onArchive()
        case .snooze:
            guard canSnooze, session.currentItem != nil else { return }
            onSnooze()
        case .reply:
            guard canReply, session.currentItem != nil else { return }
            onReply()
        case .skip:
            guard session.currentItem != nil else { return }
            onSkip()
        case .done:
            onDone()
        }
    }
    #endif
}

#if os(macOS)
/// Window-scoped local key monitor active only while `TriageView` is mounted
/// inside the key window, keeping single keys inert while typing in any text view.
private struct TriageKeyMonitorBridge: NSViewRepresentable {
    let isSuspended: Bool
    let canArchive: Bool
    let canSnooze: Bool
    let canReply: Bool
    let hasCurrentItem: Bool
    let onAction: (TriageKeyAction) -> Void

    final class Coordinator {
        var isSuspended = false
        var canArchive = false
        var canSnooze = false
        var canReply = false
        var hasCurrentItem = false
        var onAction: ((TriageKeyAction) -> Void)?
        weak var hostView: NSView?
        private var monitor: Any?

        func installIfNeeded() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return handle(event)
            }
        }

        func teardown() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            teardown()
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard !isSuspended,
                  let window = hostView?.window,
                  window.isKeyWindow,
                  window.attachedSheet == nil
            else { return event }

            let isEditingText = window.firstResponder is NSTextView
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasCommandLikeModifier = !modifiers.isDisjoint(with: [.command, .control, .option])
            let characters = event.charactersIgnoringModifiers ?? ""

            guard let action = TriageKeyboardPolicy.action(
                for: characters,
                hasModifier: hasCommandLikeModifier,
                isEditingText: isEditingText,
                canSnooze: canSnooze
            ) else { return event }

            switch action {
            case .done:
                onAction?(.done)
                return nil
            case .archive:
                guard hasCurrentItem, canArchive else { return event }
                onAction?(.archive)
                return nil
            case .snooze:
                guard hasCurrentItem, canSnooze else { return event }
                onAction?(.snooze)
                return nil
            case .reply:
                guard hasCurrentItem, canReply else { return event }
                onAction?(.reply)
                return nil
            case .skip:
                guard hasCurrentItem else { return event }
                onAction?(.skip)
                return nil
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.hostView = view
        update(coordinator: context.coordinator)
        context.coordinator.installIfNeeded()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.hostView = nsView
        update(coordinator: context.coordinator)
        context.coordinator.installIfNeeded()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    private func update(coordinator: Coordinator) {
        coordinator.isSuspended = isSuspended
        coordinator.canArchive = canArchive
        coordinator.canSnooze = canSnooze
        coordinator.canReply = canReply
        coordinator.hasCurrentItem = hasCurrentItem
        coordinator.onAction = onAction
    }
}
#endif
