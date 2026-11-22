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
#endif
import BrevAvatars
import BrevBackend
import BrevDesign
import BrevSettings
import BrevThemes
import Foundation
import Observation
import SwiftUI

/// Immutable payload displayed in the optional macOS new-mail drop-down panel (#307).
public struct NewMailPanelPayload: Equatable, Sendable {
    public let route: NotificationMailRoute
    public let senderName: String
    public let senderEmail: String
    public let previewLine: String
    public let receivedAt: Date

    public init(
        route: NotificationMailRoute,
        senderName: String,
        senderEmail: String,
        previewLine: String,
        receivedAt: Date
    ) {
        self.route = route
        self.senderName = senderName
        self.senderEmail = senderEmail
        self.previewLine = previewLine
        self.receivedAt = receivedAt
    }
}

/// Pure policy deciding whether an incoming message may appear in the optional
/// macOS new-mail drop-down panel (#307, ADR-0088).
public enum NewMailPanelPolicy {
    /// Returns a payload when the opt-in drop-down panel is enabled, the
    /// account is not muted or in quiet hours, and the message is not a
    /// sign-in code or magic-link message (ADR-0088).
    public static func payload(
        settings: NotificationSettings,
        route: NotificationMailRoute,
        correspondent: Correspondent,
        subject: String,
        snippet: String,
        receivedAt: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> NewMailPanelPayload? {
        guard settings.newMailPanelEnabled else { return nil }
        guard settings.accountOverride(for: route.accountID).notificationsEnabled else { return nil }
        guard !isQuietHour(settings: settings, now: now, calendar: calendar) else { return nil }

        // ADR-0088: sign-in codes stay out of notifications and the new-mail
        // drop-down panel until the dedicated privacy design settles.
        if containsSignInCandidate(subject: subject, snippet: snippet) {
            return nil
        }

        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSnippet = snippet.trimmingCharacters(in: .whitespacesAndNewlines)

        let senderName: String
        let senderEmail: String
        let previewLine: String

        if settings.showPreviews {
            senderName = correspondent.displayName
            senderEmail = correspondent.email
            if !trimmedSubject.isEmpty, !trimmedSnippet.isEmpty {
                previewLine = "\(trimmedSubject) — \(trimmedSnippet)"
            } else if !trimmedSubject.isEmpty {
                previewLine = trimmedSubject
            } else if !trimmedSnippet.isEmpty {
                previewLine = trimmedSnippet
            } else {
                previewLine = String(localized: "New mail", bundle: .module)
            }
        } else {
            senderName = String(localized: "New mail", bundle: .module)
            senderEmail = ""
            previewLine = String(localized: "New mail", bundle: .module)
        }

        return NewMailPanelPayload(
            route: route,
            senderName: senderName,
            senderEmail: senderEmail,
            previewLine: previewLine,
            receivedAt: receivedAt
        )
    }

    private static func containsSignInCandidate(subject: String, snippet: String) -> Bool {
        if SignInCodeDetector.detect(in: subject) != nil { return true }
        if SignInCodeDetector.detect(in: snippet) != nil { return true }
        if !subject.isEmpty, !snippet.isEmpty,
           SignInCodeDetector.detect(in: "\(subject)\n\(snippet)") != nil {
            return true
        }
        return false
    }

    private static func isQuietHour(
        settings: NotificationSettings,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard settings.quietHoursEnabled else { return false }
        let start = ((settings.quietHoursStart % 24) + 24) % 24
        let end = ((settings.quietHoursEnd % 24) + 24) % 24
        let current = calendar.component(.hour, from: now)
        if start == end { return true }
        if start < end { return current >= start && current < end }
        return current >= start || current < end
    }
}

/// Platform-neutral state controller for the auto-dismissing new-mail drop-down panel (#307).
@MainActor
@Observable
public final class NewMailPanelStateController {
    public private(set) var activePayload: NewMailPanelPayload?
    public private(set) var isHovering = false
    private let autoDismissDelay: Duration
    private var dismissTask: Task<Void, Never>?

    public init(autoDismissDelay: Duration = .seconds(6)) {
        self.autoDismissDelay = autoDismissDelay
    }

    public func present(_ payload: NewMailPanelPayload) {
        activePayload = payload
        scheduleAutoDismiss()
    }

    public func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        activePayload = nil
        isHovering = false
    }

    public func setHovering(_ hovering: Bool) {
        isHovering = hovering
        if hovering {
            dismissTask?.cancel()
            dismissTask = nil
        } else if activePayload != nil {
            scheduleAutoDismiss()
        }
    }

    private func scheduleAutoDismiss() {
        dismissTask?.cancel()
        let delay = autoDismissDelay
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled, !self.isHovering else { return }
            dismiss()
        }
    }
}

/// Compact drop-down card shown near the macOS menu bar / notch for incoming mail (#307).
struct NewMailDropDownPanelView: View {
    @Environment(\.brevTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 28

    let payload: NewMailPanelPayload
    let onArchive: () -> Void
    let onMarkRead: () -> Void
    let onReply: () -> Void
    let onDismiss: () -> Void
    let onHoverChanged: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            HStack(alignment: .top, spacing: BrevSpacing.sm) {
                Text(verbatim: InitialsAvatar.initials(
                    displayName: payload.senderName,
                    email: payload.senderEmail
                ))
                .brevFont(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(theme.textSecondary.color)
                .frame(width: avatarSize, height: avatarSize)
                .background(Circle().fill(theme.bgTertiary.color))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: BrevSpacing.xs) {
                        Text(verbatim: payload.senderName)
                            .brevFont(.callout)
                            .fontWeight(.semibold)
                            .foregroundStyle(theme.textPrimary.color)
                            .lineLimit(1)
                        Spacer(minLength: BrevSpacing.xs)
                        Button {
                            onDismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(theme.textTertiary.color)
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Dismiss", bundle: .module))
                    }

                    Text(verbatim: payload.previewLine)
                        .brevFont(.callout)
                        .foregroundStyle(theme.textSecondary.color)
                        .lineLimit(1)
                }
            }

            HStack(spacing: BrevSpacing.xs) {
                actionButton(
                    title: String(localized: "Archive", bundle: .module),
                    systemImage: "archivebox",
                    action: onArchive
                )
                actionButton(
                    title: String(localized: "Mark as Read", bundle: .module),
                    systemImage: "envelope.open",
                    action: onMarkRead
                )
                actionButton(
                    title: String(localized: "Reply", bundle: .module),
                    systemImage: "arrowshape.turn.up.left",
                    action: onReply
                )
                Spacer(minLength: 0)
            }
        }
        .padding(BrevSpacing.md)
        .frame(width: 380, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BrevRadius.lg)
                .fill(theme.bgSecondary.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BrevRadius.lg)
                .strokeBorder(theme.border.color, lineWidth: 0.75)
        )
        .onHover { hovering in
            onHoverChanged(hovering)
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                Text(verbatim: title)
                    .brevFont(.caption)
            }
            .foregroundStyle(theme.textPrimary.color)
            .padding(.horizontal, BrevSpacing.sm)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(theme.bgPrimary.color)
            )
            .overlay(
                Capsule()
                    .strokeBorder(theme.border.color, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Non-activating top-of-screen `NSPanel` presenter for incoming mail (#307).
/// Reuses the ADR-0088 floating-panel non-activating window configuration on
/// macOS; inert no-op on iOS so cross-platform call sites stay uniform.
@MainActor
public final class NewMailDropDownPanelController {
    private let stateController: NewMailPanelStateController
    #if os(macOS)
    private var panel: NSPanel?
    private var settingsObserver: NSObjectProtocol?
    private var watchTask: Task<Void, Never>?
    #endif

    public init(autoDismissDelay: Duration = .seconds(6)) {
        stateController = NewMailPanelStateController(autoDismissDelay: autoDismissDelay)
        #if os(macOS)
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .brevNotificationSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                if !NotificationSettings.load().newMailPanelEnabled {
                    self?.dismiss()
                }
            }
        }
        #endif
    }

    #if os(macOS)
    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }
    #endif

    public func present(
        payload: NewMailPanelPayload,
        theme: BrevTheme,
        onArchive: @escaping @MainActor () -> Void,
        onMarkRead: @escaping @MainActor () -> Void,
        onReply: @escaping @MainActor () -> Void
    ) {
        #if os(macOS)
        stateController.present(payload)
        let rootView = NewMailDropDownPanelView(
            payload: payload,
            onArchive: { [weak self] in
                self?.dismiss()
                onArchive()
            },
            onMarkRead: { [weak self] in
                self?.dismiss()
                onMarkRead()
            },
            onReply: { [weak self] in
                self?.dismiss()
                onReply()
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            },
            onHoverChanged: { [weak self] hovering in
                self?.stateController.setHovering(hovering)
            }
        )
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)

        let hosting = NSHostingController(rootView: rootView)
        let targetPanel = ensurePanel()
        targetPanel.contentViewController = hosting
        targetPanel.appearance = NSAppearance(named: theme.mode == .dark ? .darkAqua : .aqua)

        let fittingSize = hosting.view.fittingSize
        let size = NSSize(
            width: max(380, fittingSize.width),
            height: max(96, fittingSize.height)
        )
        positionTopCenter(panel: targetPanel, size: size)
        targetPanel.orderFrontRegardless()
        startAutoCloseWatcher()
        #endif
    }

    public func dismiss() {
        #if os(macOS)
        watchTask?.cancel()
        watchTask = nil
        stateController.dismiss()
        panel?.orderOut(nil)
        #endif
    }

    #if os(macOS)
    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let created = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 108),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        created.isOpaque = false
        created.backgroundColor = .clear
        created.hasShadow = true
        created.level = .floating
        created.hidesOnDeactivate = false
        created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel = created
        return created
    }

    private func positionTopCenter(panel: NSPanel, size: NSSize) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else {
            panel.setContentSize(size)
            return
        }
        let origin = NSPoint(
            x: round(visible.midX - size.width / 2),
            y: round(visible.maxY - size.height - 10)
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func startAutoCloseWatcher() {
        watchTask?.cancel()
        watchTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                if stateController.activePayload == nil {
                    panel?.orderOut(nil)
                    break
                }
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }
    #endif
}
