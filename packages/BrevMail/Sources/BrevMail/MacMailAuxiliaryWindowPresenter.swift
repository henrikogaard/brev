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
import SwiftUI

struct MacMailAuxiliaryWindowConfiguration: Equatable {
    let title: String
    let defaultSize: CGSize
    let minimumSize: CGSize
    let frameAutosaveName: String
    let styleMask: NSWindow.StyleMask
    let titleVisibility: NSWindow.TitleVisibility
    let titlebarAppearsTransparent: Bool
    let toolbarStyle: NSWindow.ToolbarStyle
    let isMovableByWindowBackground: Bool

    static func configuration(for sheet: MailNavigationState.Sheet) -> Self {
        switch sheet {
        case .compose:
            return Self(
                title: "Compose",
                defaultSize: CGSize(width: 820, height: 700),
                minimumSize: CGSize(width: 680, height: 560),
                frameAutosaveName: "BrevComposeWindow",
                styleMask: composeStyleMask,
                titleVisibility: .hidden,
                titlebarAppearsTransparent: true,
                toolbarStyle: .automatic,
                isMovableByWindowBackground: false
            )
        case .profiles:
            return Self(
                title: "Profiles",
                defaultSize: CGSize(width: 620, height: 520),
                minimumSize: CGSize(width: 520, height: 420),
                frameAutosaveName: "BrevProfilesWindow",
                styleMask: standardStyleMask,
                titleVisibility: .visible,
                titlebarAppearsTransparent: false,
                toolbarStyle: .automatic,
                isMovableByWindowBackground: false
            )
        case .themePicker:
            return Self(
                title: "Theme",
                defaultSize: CGSize(width: 400, height: 520),
                minimumSize: CGSize(width: 340, height: 420),
                frameAutosaveName: "BrevThemeWindow",
                styleMask: standardStyleMask,
                titleVisibility: .visible,
                titlebarAppearsTransparent: false,
                toolbarStyle: .automatic,
                isMovableByWindowBackground: false
            )
        case .mailboxAssistant:
            return Self(
                title: "Mailbox Assistant",
                defaultSize: CGSize(width: 460, height: 520),
                minimumSize: CGSize(width: 360, height: 360),
                frameAutosaveName: "BrevMailboxAssistantWindow",
                styleMask: standardStyleMask,
                titleVisibility: .hidden,
                titlebarAppearsTransparent: true,
                toolbarStyle: .unifiedCompact,
                isMovableByWindowBackground: true
            )
        case .createTask:
            return Self(
                title: "Create Task",
                defaultSize: CGSize(width: 460, height: 520),
                minimumSize: CGSize(width: 380, height: 440),
                frameAutosaveName: "BrevCreateTaskWindow",
                styleMask: standardStyleMask,
                titleVisibility: .hidden,
                titlebarAppearsTransparent: true,
                toolbarStyle: .unifiedCompact,
                isMovableByWindowBackground: true
            )
        case .createRule:
            return Self(
                title: "Create Rule",
                defaultSize: CGSize(width: 460, height: 560),
                minimumSize: CGSize(width: 380, height: 460),
                frameAutosaveName: "BrevCreateRuleWindow",
                styleMask: standardStyleMask,
                titleVisibility: .hidden,
                titlebarAppearsTransparent: true,
                toolbarStyle: .unifiedCompact,
                isMovableByWindowBackground: true
            )
        case .createMeeting:
            return Self(
                title: "Create Meeting",
                defaultSize: CGSize(width: 460, height: 600),
                minimumSize: CGSize(width: 380, height: 480),
                frameAutosaveName: "BrevCreateMeetingWindow",
                styleMask: standardStyleMask,
                titleVisibility: .hidden,
                titlebarAppearsTransparent: true,
                toolbarStyle: .unifiedCompact,
                isMovableByWindowBackground: true
            )
        case .messageNote:
            return Self(
                title: "Message Note",
                defaultSize: CGSize(width: 460, height: 420),
                minimumSize: CGSize(width: 380, height: 340),
                frameAutosaveName: "BrevMessageNoteWindow",
                styleMask: standardStyleMask,
                titleVisibility: .hidden,
                titlebarAppearsTransparent: true,
                toolbarStyle: .unifiedCompact,
                isMovableByWindowBackground: true
            )
        case .followUp:
            return Self(
                title: String(localized: "Follow Up", bundle: .module),
                defaultSize: CGSize(width: 460, height: 520),
                minimumSize: CGSize(width: 380, height: 420),
                frameAutosaveName: "BrevFollowUpWindow",
                styleMask: standardStyleMask,
                titleVisibility: .hidden,
                titlebarAppearsTransparent: true,
                toolbarStyle: .unifiedCompact,
                isMovableByWindowBackground: true
            )
        case .moveTo:
            return Self(
                title: "Move To",
                defaultSize: CGSize(width: 380, height: 480),
                minimumSize: CGSize(width: 320, height: 360),
                frameAutosaveName: "BrevMoveToWindow",
                styleMask: standardStyleMask,
                titleVisibility: .hidden,
                titlebarAppearsTransparent: true,
                toolbarStyle: .unifiedCompact,
                isMovableByWindowBackground: true
            )
        case .copyTo:
            return Self(
                title: "Copy To",
                defaultSize: CGSize(width: 380, height: 480),
                minimumSize: CGSize(width: 320, height: 360),
                frameAutosaveName: "BrevCopyToWindow",
                styleMask: standardStyleMask,
                titleVisibility: .hidden,
                titlebarAppearsTransparent: true,
                toolbarStyle: .unifiedCompact,
                isMovableByWindowBackground: true
            )
        case .messageProperties:
            return Self(
                title: "Message Properties",
                defaultSize: CGSize(width: 440, height: 420),
                minimumSize: CGSize(width: 360, height: 320),
                frameAutosaveName: "BrevMessagePropertiesWindow",
                styleMask: standardStyleMask,
                titleVisibility: .hidden,
                titlebarAppearsTransparent: true,
                toolbarStyle: .unifiedCompact,
                isMovableByWindowBackground: true
            )
        case .viewSource, .showHeaders:
            return Self(
                title: "Message Source",
                defaultSize: CGSize(width: 600, height: 560),
                minimumSize: CGSize(width: 440, height: 360),
                frameAutosaveName: "BrevMessageSourceWindow",
                styleMask: standardStyleMask,
                titleVisibility: .hidden,
                titlebarAppearsTransparent: true,
                toolbarStyle: .unifiedCompact,
                isMovableByWindowBackground: true
            )
        case .outbox:
            return Self(
                title: "Outbox",
                defaultSize: CGSize(width: 420, height: 480),
                minimumSize: CGSize(width: 340, height: 360),
                frameAutosaveName: "BrevOutboxWindow",
                styleMask: standardStyleMask,
                titleVisibility: .visible,
                titlebarAppearsTransparent: false,
                toolbarStyle: .automatic,
                isMovableByWindowBackground: false
            )
        }
    }

    private static let standardStyleMask: NSWindow.StyleMask = [
        .titled,
        .closable,
        .miniaturizable,
        .resizable
    ]

    private static let composeStyleMask: NSWindow.StyleMask = [
        .titled,
        .closable,
        .miniaturizable,
        .resizable,
        .fullSizeContentView
    ]
}

enum MacMailAuxiliaryWindowActivationPolicy {
    static func shouldActivate(
        hasWindow: Bool,
        activeSheet: MailNavigationState.Sheet?,
        presentedSheet: MailNavigationState.Sheet
    ) -> Bool {
        !hasWindow || activeSheet != presentedSheet
    }
}

enum MacMailAuxiliaryWindowPlacementPolicy {
    static func constrainedFrame(
        _ frame: CGRect,
        visibleFrame: CGRect,
        margin: CGFloat = 24
    ) -> CGRect {
        guard visibleFrame.width > 0, visibleFrame.height > 0 else {
            return frame
        }

        let horizontalMargin = min(margin, visibleFrame.width / 2)
        let verticalMargin = min(margin, visibleFrame.height / 2)
        let maxWidth = max(1, visibleFrame.width - horizontalMargin * 2)
        let maxHeight = max(1, visibleFrame.height - verticalMargin * 2)
        let width = min(frame.width, maxWidth)
        let height = min(frame.height, maxHeight)

        let minX = visibleFrame.minX + horizontalMargin
        let maxX = visibleFrame.maxX - horizontalMargin - width
        let minY = visibleFrame.minY + verticalMargin
        let maxY = visibleFrame.maxY - verticalMargin - height

        return CGRect(
            x: clampedOrigin(frame.minX, minimum: minX, maximum: maxX),
            y: clampedOrigin(frame.minY, minimum: minY, maximum: maxY),
            width: width,
            height: height
        )
    }

    private static func clampedOrigin(
        _ value: CGFloat,
        minimum: CGFloat,
        maximum: CGFloat
    ) -> CGFloat {
        if maximum < minimum {
            return minimum
        }
        return min(max(value, minimum), maximum)
    }
}

struct MacMailAuxiliaryWindowPresenter: NSViewRepresentable {
    @Binding var sheet: MailNavigationState.Sheet?
    let makeContent: (MailNavigationState.Sheet, @escaping () -> Void) -> AnyView

    func makeCoordinator() -> Coordinator {
        Coordinator(sheet: $sheet, makeContent: makeContent)
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.update(
            sheet: $sheet,
            makeContent: makeContent,
            ownerView: view
        )
    }

    static func dismantleNSView(_: NSView, coordinator: Coordinator) {
        coordinator.closeWindow(updateBinding: false)
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        private var sheet: Binding<MailNavigationState.Sheet?>
        private var makeContent: (MailNavigationState.Sheet, @escaping () -> Void) -> AnyView
        private weak var ownerView: NSView?
        private var window: NSWindow?
        private var hostingController: NSHostingController<AnyView>?
        private var activeSheet: MailNavigationState.Sheet?

        init(
            sheet: Binding<MailNavigationState.Sheet?>,
            makeContent: @escaping (MailNavigationState.Sheet, @escaping () -> Void) -> AnyView
        ) {
            self.sheet = sheet
            self.makeContent = makeContent
        }

        func update(
            sheet: Binding<MailNavigationState.Sheet?>,
            makeContent: @escaping (MailNavigationState.Sheet, @escaping () -> Void) -> AnyView,
            ownerView: NSView
        ) {
            self.sheet = sheet
            self.makeContent = makeContent
            self.ownerView = ownerView

            guard let presentedSheet = sheet.wrappedValue else {
                closeWindow(updateBinding: false)
                return
            }

            present(presentedSheet)
        }

        func closeWindow(updateBinding: Bool) {
            if updateBinding {
                sheet.wrappedValue = nil
            }

            guard let window else {
                hostingController = nil
                activeSheet = nil
                return
            }

            window.delegate = nil
            window.close()
            self.window = nil
            hostingController = nil
            activeSheet = nil
        }

        func windowWillClose(_ notification: Notification) {
            guard notification.object as? NSWindow === window else { return }
            sheet.wrappedValue = nil
            window?.delegate = nil
            window = nil
            hostingController = nil
            activeSheet = nil
        }

        private func present(_ presentedSheet: MailNavigationState.Sheet) {
            let close: () -> Void = { [weak self] in
                self?.sheet.wrappedValue = nil
                self?.closeWindow(updateBinding: false)
            }
            let rootView = makeContent(presentedSheet, close)
            let shouldActivate = MacMailAuxiliaryWindowActivationPolicy.shouldActivate(
                hasWindow: window != nil,
                activeSheet: activeSheet,
                presentedSheet: presentedSheet
            )

            if window == nil || activeSheet != presentedSheet {
                closeWindow(updateBinding: false)
                createWindow(for: presentedSheet, rootView: rootView)
            } else {
                hostingController?.rootView = rootView
            }

            if shouldActivate {
                window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        private func createWindow(
            for sheet: MailNavigationState.Sheet,
            rootView: AnyView
        ) {
            let configuration = MacMailAuxiliaryWindowConfiguration.configuration(for: sheet)
            let hostingController = NSHostingController(rootView: rootView)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: configuration.defaultSize),
                styleMask: configuration.styleMask,
                backing: .buffered,
                defer: false
            )

            window.title = configuration.title
            window.minSize = configuration.minimumSize
            window.contentMinSize = configuration.minimumSize
            window.titleVisibility = configuration.titleVisibility
            window.titlebarAppearsTransparent = configuration.titlebarAppearsTransparent
            window.toolbarStyle = configuration.toolbarStyle
            window.isMovableByWindowBackground = configuration.isMovableByWindowBackground
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.delegate = self
            window.contentViewController = hostingController
            window.center()
            _ = window.setFrameAutosaveName(configuration.frameAutosaveName)

            if let parentFrame = ownerView?.window?.frame, window.frame.origin == .zero {
                window.setFrameOrigin(
                    CGPoint(
                        x: parentFrame.midX - configuration.defaultSize.width / 2,
                        y: parentFrame.midY - configuration.defaultSize.height / 2
                    )
                )
            }

            constrainToVisibleScreen(window)

            self.window = window
            self.hostingController = hostingController
            activeSheet = sheet
        }

        private func constrainToVisibleScreen(_ window: NSWindow) {
            guard let visibleFrame = (
                window.screen
                    ?? ownerView?.window?.screen
                    ?? NSScreen.main
            )?.visibleFrame else {
                return
            }

            let constrainedFrame = MacMailAuxiliaryWindowPlacementPolicy.constrainedFrame(
                window.frame,
                visibleFrame: visibleFrame
            )
            if constrainedFrame != window.frame {
                window.setFrame(constrainedFrame, display: false)
            }
        }
    }
}
#endif
