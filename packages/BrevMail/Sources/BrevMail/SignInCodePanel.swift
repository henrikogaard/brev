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
#elseif os(iOS)
import UIKit
#endif
import BrevDesign
import BrevSettings
import BrevThemes
import Foundation
import Observation
import SwiftUI

/// Formatting and local expiry helpers for sign-in code surfaces (#239, ADR-0088).
public enum SignInCodePresentationFormat {
    /// Groups 6- and 8-character codes for easy reading (`525-488`, `1234-5678`)
    /// while leaving shorter or odd-length codes intact.
    public static func groupedCode(_ code: String) -> String {
        let chars = Array(code)
        switch chars.count {
        case 6:
            return String(chars[0 ..< 3]) + "-" + String(chars[3 ..< 6])
        case 8:
            return String(chars[0 ..< 4]) + "-" + String(chars[4 ..< 8])
        default:
            return code
        }
    }

    /// Local-only time rule: codes older than 10 minutes are labelled probably expired.
    public static func isProbablyExpired(
        sentAt: Date,
        now: Date = Date(),
        expiryWindow: TimeInterval = 600
    ) -> Bool {
        now.timeIntervalSince(sentAt) >= expiryWindow
    }
}

/// Concealed pasteboard writer for sign-in codes (ADR-0088 §8).
@MainActor
public protocol SignInCodePasteboardWriting: AnyObject {
    /// Writes `value` marked as concealed/local-only and returns the resulting
    /// pasteboard `changeCount`.
    func writeConcealed(_ value: String) -> Int

    /// Clears the pasteboard only if `changeCount` still equals `expectedChangeCount`.
    func clearIfUnchanged(expectedChangeCount: Int)
}

/// System pasteboard implementation honoring ADR-0088 §8:
/// - macOS writes `org.nspasteboard.ConcealedType` alongside `.string` and only
///   clears when `NSPasteboard.general.changeCount` is unchanged.
/// - iOS writes `.localOnly` with a 60-second expiration date.
@MainActor
public final class SystemSignInCodePasteboard: SignInCodePasteboardWriting {
    #if os(macOS)
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    #endif

    public nonisolated init() {}

    public func writeConcealed(_ value: String) -> Int {
        #if os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(value, forType: .string)
        pb.setData(Data(), forType: Self.concealedType)
        return pb.changeCount
        #elseif os(iOS)
        let pb = UIPasteboard.general
        pb.setItems(
            [[UIPasteboard.typeAutomatic: value]],
            options: [
                .localOnly: true,
                .expirationDate: Date().addingTimeInterval(60),
            ]
        )
        return pb.changeCount
        #else
        return 0
        #endif
    }

    public func clearIfUnchanged(expectedChangeCount: Int) {
        #if os(macOS)
        let pb = NSPasteboard.general
        guard pb.changeCount == expectedChangeCount else { return }
        pb.clearContents()
        #elseif os(iOS)
        let pb = UIPasteboard.general
        guard pb.changeCount == expectedChangeCount else { return }
        pb.items = []
        #endif
    }
}

/// Memory-only state machine for the macOS sign-in panel (#239, ADR-0088 §7–§9).
@MainActor
@Observable
public final class SignInCodePanelStateController: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public static let maxQueueDepth = 3

    public private(set) var activePresentation: SignInCodePresentation?
    public private(set) var didCopyActiveCode = false
    private var queue: [SignInCodePresentation] = []
    private let pasteboard: any SignInCodePasteboardWriting
    private let clipboardClearDelay: Duration?
    private let copiedDismissDelay: Duration
    private let isAppActive: @MainActor () -> Bool
    private var timeoutTask: Task<Void, Never>?
    private var copiedDismissTask: Task<Void, Never>?
    private var clipboardClearTask: Task<Void, Never>?

    public var queuedCount: Int { queue.count }

    public nonisolated var description: String { "SignInCodePanelStateController(redacted)" }
    public nonisolated var debugDescription: String { description }
    public nonisolated var customMirror: Mirror { Mirror(self, children: EmptyCollection<Mirror.Child>()) }

    public init(
        pasteboard: any SignInCodePasteboardWriting = SystemSignInCodePasteboard(),
        clipboardClearDelay: Duration? = .seconds(60),
        copiedDismissDelay: Duration = .milliseconds(700),
        isAppActive: @escaping @MainActor () -> Bool = {
            #if os(macOS)
            NSApp.isActive
            #else
            true
            #endif
        }
    ) {
        self.pasteboard = pasteboard
        self.clipboardClearDelay = clipboardClearDelay
        self.copiedDismissDelay = copiedDismissDelay
        self.isAppActive = isAppActive
    }

    public func present(_ presentation: SignInCodePresentation) {
        // ADR-0088 §9: a newer code/link from the same account and sender
        // replaces the older one instead of stacking.
        if let active = activePresentation,
           active.accountID == presentation.accountID,
           active.sender.caseInsensitiveCompare(presentation.sender) == .orderedSame {
            activate(presentation)
            return
        }

        queue.removeAll {
            $0.accountID == presentation.accountID
                && $0.sender.caseInsensitiveCompare(presentation.sender) == .orderedSame
        }

        if activePresentation == nil {
            activate(presentation)
        } else {
            if queue.count >= Self.maxQueueDepth {
                queue.removeFirst()
            }
            queue.append(presentation)
        }
    }

    public func dismiss(accountID: String) {
        queue.removeAll { $0.accountID == accountID }
        if activePresentation?.accountID == accountID {
            dismissActive()
        }
    }

    public func dismissActive() {
        timeoutTask?.cancel()
        timeoutTask = nil
        copiedDismissTask?.cancel()
        copiedDismissTask = nil
        didCopyActiveCode = false
        if !queue.isEmpty {
            let next = queue.removeFirst()
            activate(next)
        } else {
            activePresentation = nil
        }
    }

    /// ADR-0088 §9: Escape dismisses the panel ONLY while Brev is the active app.
    @discardableResult
    public func handleEscapeKey() -> Bool {
        guard activePresentation != nil, isAppActive() else { return false }
        dismissActive()
        return true
    }

    /// Copies the active code with `org.nspasteboard.ConcealedType`, shows
    /// brief "Copied" confirmation, schedules conditional clipboard clear, and
    /// dismisses the panel.
    public func copyActiveCode() {
        guard let active = activePresentation,
              case .code(let rawCode) = active.content else { return }
        let changeCount = pasteboard.writeConcealed(rawCode)
        didCopyActiveCode = true

        if let clearDelay = clipboardClearDelay {
            clipboardClearTask?.cancel()
            clipboardClearTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: clearDelay)
                guard let self, !Task.isCancelled else { return }
                pasteboard.clearIfUnchanged(expectedChangeCount: changeCount)
            }
        }

        let dismissDelay = copiedDismissDelay
        copiedDismissTask?.cancel()
        copiedDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: dismissDelay)
            guard let self, !Task.isCancelled else { return }
            dismissActive()
        }
    }

    private func activate(_ presentation: SignInCodePresentation) {
        copiedDismissTask?.cancel()
        copiedDismissTask = nil
        didCopyActiveCode = false
        activePresentation = presentation
        scheduleTimeout(seconds: presentation.timeout)
    }

    private func scheduleTimeout(seconds: TimeInterval) {
        timeoutTask?.cancel()
        let clamped = max(1, seconds)
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(clamped))
            guard let self, !Task.isCancelled else { return }
            dismissActive()
        }
    }
}

/// Compact floating pill view for a one-time sign-in code or magic link (#239, ADR-0088).
struct SignInCodePanelView: View {
    @Environment(\.brevTheme) private var theme

    let presentation: SignInCodePresentation
    let didCopy: Bool
    let onCopy: () -> Void
    let onOpenLink: (URL) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: BrevSpacing.md) {
            switch presentation.content {
            case .code(let code):
                codeContent(code: code)
            case .link(let destination, let host):
                linkContent(destination: destination, host: host)
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.textTertiary.color)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Dismiss", bundle: .module))
        }
        .padding(.horizontal, BrevSpacing.md)
        .padding(.vertical, BrevSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: BrevRadius.lg)
                .fill(theme.bgSecondary.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BrevRadius.lg)
                .strokeBorder(theme.border.color, lineWidth: 0.75)
        )
    }

    @ViewBuilder
    private func codeContent(code: String) -> some View {
        Image(systemName: "key.viewfinder")
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(theme.accent.color)
            .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: SignInCodePresentationFormat.groupedCode(code))
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.textPrimary.color)
                .monospacedDigit()
            Text(verbatim: presentation.sender.isEmpty ? String(localized: "Sign-in code", bundle: .module) : presentation.sender)
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
                .lineLimit(1)
        }

        Spacer(minLength: BrevSpacing.sm)

        Button {
            onCopy()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                Text(
                    didCopy
                        ? String(localized: "Copied", bundle: .module)
                        : String(localized: "Copy", bundle: .module)
                )
                .brevFont(.caption)
                .fontWeight(.semibold)
            }
            .foregroundStyle(theme.bgPrimary.color)
            .padding(.horizontal, BrevSpacing.sm)
            .padding(.vertical, 6)
            .background(Capsule().fill(theme.accent.color))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func linkContent(destination: String, host: String) -> some View {
        Image(systemName: "link")
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(theme.accent.color)
            .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 2) {
            Text(
                verbatim: String(
                    format: String(localized: "%@ sent a sign-in link", bundle: .module),
                    presentation.sender.isEmpty ? host : presentation.sender
                )
            )
            .brevFont(.callout)
            .fontWeight(.semibold)
            .foregroundStyle(theme.textPrimary.color)
            .lineLimit(1)

            HStack(spacing: BrevSpacing.xs) {
                Text("Click to open it in your browser", bundle: .module)
                    .brevFont(.caption)
                    .foregroundStyle(theme.textSecondary.color)
                    .lineLimit(1)
                Text(verbatim: host)
                    .brevFont(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(theme.textPrimary.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(theme.bgTertiary.color))
            }
        }

        Spacer(minLength: BrevSpacing.sm)

        Button {
            if let url = URL(string: destination), url.scheme?.lowercased() == "https" {
                onOpenLink(url)
            }
        } label: {
            Text("Open", bundle: .module)
                .brevFont(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(theme.bgPrimary.color)
                .padding(.horizontal, BrevSpacing.sm)
                .padding(.vertical, 6)
                .background(Capsule().fill(theme.accent.color))
        }
        .buttonStyle(.plain)
    }
}

/// Non-activating bottom-center `NSPanel` presenter conforming to
/// `SignInCodePresenting` (#239, ADR-0088 §9).
///
/// On iOS this type is an inert no-op because iOS notifications stay blocked
/// until the iOS privacy ADR amendment is accepted.
@MainActor
public final class SignInCodePanelController: SignInCodePresenting {
    public let stateController: SignInCodePanelStateController
    public var themeProvider: @MainActor () -> BrevTheme
    #if os(macOS)
    private var panel: NSPanel?
    private var localKeyMonitor: Any?
    private var watchTask: Task<Void, Never>?
    #endif

    public init(
        themeProvider: @escaping @MainActor () -> BrevTheme = { .brevMonoLight },
        pasteboard: any SignInCodePasteboardWriting = SystemSignInCodePasteboard()
    ) {
        self.themeProvider = themeProvider
        stateController = SignInCodePanelStateController(pasteboard: pasteboard)
    }

    public func present(_ presentation: SignInCodePresentation) {
        #if os(macOS)
        stateController.present(presentation)
        renderCurrentPanel()
        #endif
    }

    public func dismiss(accountID: String) {
        #if os(macOS)
        stateController.dismiss(accountID: accountID)
        renderCurrentPanel()
        #endif
    }

    #if os(macOS)
    private func renderCurrentPanel() {
        guard let active = stateController.activePresentation else {
            hidePanel()
            return
        }
        let theme = themeProvider()
        let rootView = SignInCodePanelHostView(
            stateController: stateController,
            onOpenLink: { [weak self] url in
                NSWorkspace.shared.open(url)
                self?.stateController.dismissActive()
                self?.renderCurrentPanel()
            }
        )
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)

        let hosting = NSHostingController(rootView: rootView)
        let targetPanel = ensurePanel()
        targetPanel.contentViewController = hosting
        targetPanel.appearance = NSAppearance(named: theme.mode == .dark ? .darkAqua : .aqua)

        let fitting = hosting.view.fittingSize
        let size = NSSize(width: max(360, fitting.width), height: max(68, fitting.height))
        positionBottomCenter(panel: targetPanel, size: size)
        targetPanel.orderFrontRegardless()
        installAppLocalEscapeMonitor()
        startAutoHideWatcher()
        _ = active
    }

    private func hidePanel() {
        watchTask?.cancel()
        watchTask = nil
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let created = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 74),
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

    private func positionBottomCenter(panel: NSPanel, size: NSSize) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else {
            panel.setContentSize(size)
            return
        }
        let origin = NSPoint(
            x: round(visible.midX - size.width / 2),
            y: round(visible.minY + 32)
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    /// ADR-0088 §9: App-local key monitor only — never a global monitor, never
    /// requests Accessibility/Input Monitoring, and never consumes Escape when
    /// another app is active.
    private func installAppLocalEscapeMonitor() {
        guard localKeyMonitor == nil else { return }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                let dismissed = self.stateController.handleEscapeKey()
                if dismissed {
                    self.renderCurrentPanel()
                }
                return dismissed
            }
            return handled ? nil : event
        }
    }

    private func startAutoHideWatcher() {
        watchTask?.cancel()
        watchTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                if stateController.activePresentation == nil {
                    hidePanel()
                    break
                }
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }
    #endif
}

#if os(macOS)
private struct SignInCodePanelHostView: View {
    let stateController: SignInCodePanelStateController
    let onOpenLink: (URL) -> Void

    var body: some View {
        if let active = stateController.activePresentation {
            SignInCodePanelView(
                presentation: active,
                didCopy: stateController.didCopyActiveCode,
                onCopy: { stateController.copyActiveCode() },
                onOpenLink: onOpenLink,
                onDismiss: { stateController.dismissActive() }
            )
        }
    }
}
#endif
