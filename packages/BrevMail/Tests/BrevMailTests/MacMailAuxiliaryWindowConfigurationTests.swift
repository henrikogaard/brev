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
@testable import BrevMail
import SwiftUI
import Testing

@Suite("MacMailAuxiliaryWindowConfiguration")
struct MacMailAuxiliaryWindowConfigurationTests {
    @Test("Command-Return reaches a detached composer's toolbar with Caps Lock off or on", arguments: [
        false, true
    ], [NSEvent.ModifierFlags.command, [.command, .capsLock]])
    @MainActor
    func composeAcceleratorReachesToolbar(fieldFocus: Bool, modifiers: NSEvent.ModifierFlags) throws {
        var invocations = 0
        let fixture = ComposeAcceleratorFixture { invocations += 1 }
        let window = fixture.window
        defer { window.close() }
        #expect(window.toolbar?.items.contains { $0.itemIdentifier == MacComposeToolbarItemIdentifier.send } == true)
        let responder: NSView = fieldFocus ? NSTextField() : NSTextView()
        fixture.host.view.addSubview(responder)
        #expect(window.makeFirstResponder(responder))
        #expect(window.firstResponder is NSTextView)

        #expect(try window.performKeyEquivalent(with: fixture.event(modifiers: modifiers)))
        #expect(invocations == 1)
    }

    @Test("compose accelerator rejects other modifier combinations", arguments: [
        NSEvent.ModifierFlags(), .shift, .option, .control,
        [.command, .shift], [.command, .option], [.command, .control], [.command, .function],
        .capsLock, [.command, .capsLock, .shift], [.command, .capsLock, .option],
        [.command, .capsLock, .control], [.command, .capsLock, .function]
    ])
    @MainActor
    func composeAcceleratorRejectsModifiers(modifiers: NSEvent.ModifierFlags) throws {
        var invocations = 0
        let fixture = ComposeAcceleratorFixture { invocations += 1 }
        defer { fixture.window.close() }

        #expect(try !fixture.window.performKeyEquivalent(with: fixture.event(modifiers: modifiers)))
        #expect(invocations == 0)
    }

    @Test("compose accelerator leaves other keys and key-up events unhandled", arguments: [
        NSEvent.ModifierFlags.command, [.command, .capsLock]
    ])
    @MainActor
    func composeAcceleratorRejectsOtherKeys(modifiers: NSEvent.ModifierFlags) throws {
        var invocations = 0
        let fixture = ComposeAcceleratorFixture { invocations += 1 }
        defer { fixture.window.close() }

        for keyCode: UInt16 in [0, 48, 53, 76] {
            #expect(try !fixture.window.performKeyEquivalent(with: fixture.event(modifiers: modifiers, keyCode: keyCode)))
        }
        #expect(try !fixture.window.performKeyEquivalent(with: fixture.event(modifiers: modifiers, type: .keyUp)))
        #expect(invocations == 0)
    }

    @Test("compose accelerator consumes auto-repeat without sending or cancelling twice")
    @MainActor
    func composeAcceleratorIgnoresAutoRepeat() throws {
        var invocations = 0
        let fixture = ComposeAcceleratorFixture { invocations += 1 }
        defer { fixture.window.close() }

        #expect(try fixture.window.performKeyEquivalent(with: fixture.event()))
        for _ in 0 ..< 3 {
            #expect(try fixture.window.performKeyEquivalent(with: fixture.event(isRepeat: true)))
        }
        #expect(invocations == 1)
        // A fresh press must still reach Cancel Send when undo-send is pending.
        #expect(try fixture.window.performKeyEquivalent(with: fixture.event(timestamp: 2)))
        #expect(invocations == 2)
    }

    @Test("disabled compose actions do not fall through and bridge updates restore the latest action")
    @MainActor
    func composeAcceleratorRespectsDisabledAndUpdatedActions() throws {
        var invocations = 0
        let fixture = ComposeAcceleratorFixture { invocations += 1 }
        defer { fixture.window.close() }
        fixture.bridge.sendAction = nil
        fixture.bridge.updateToolbar()
        #expect(try fixture.window.performKeyEquivalent(with: fixture.event()))
        #expect(invocations == 0)

        fixture.bridge.sendAction = { invocations += 10 }
        fixture.bridge.updateToolbar()
        #expect(try fixture.window.performKeyEquivalent(with: fixture.event()))
        #expect(invocations == 10)

        fixture.bridge.removeFromSuperview()
        #expect(fixture.delegate.sendAction == nil)
        #expect(try fixture.window.performKeyEquivalent(with: fixture.event()))
        #expect(invocations == 10)
    }

    @Test("compose shortcuts cannot target another window or an auxiliary window without compose toolbar")
    @MainActor
    func composeAcceleratorIsWindowScoped() throws {
        var firstInvocations = 0
        var secondInvocations = 0
        let first = ComposeAcceleratorFixture { firstInvocations += 1 }
        let second = ComposeAcceleratorFixture { secondInvocations += 1 }
        defer { first.window.close(); second.window.close() }

        #expect(try !first.window.performKeyEquivalent(with: second.event()))
        #expect(firstInvocations == 0)
        #expect(secondInvocations == 0)
        #expect(try second.window.performKeyEquivalent(with: second.event()))
        #expect(firstInvocations == 0)
        #expect(secondInvocations == 1)

        first.window.toolbar = nil
        #expect(try !first.window.performKeyEquivalent(with: first.event()))
        #expect(firstInvocations == 0)
    }

    @Test("source contract: native and pointer Send share the live compose guards and undo action")
    func composeAcceleratorUsesSharedSendAction() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/BrevMail")
        let compose = try String(contentsOf: sources.appendingPathComponent("ComposeView.swift"), encoding: .utf8)
        let presenter = try String(
            contentsOf: sources.appendingPathComponent("MacMailAuxiliaryWindowPresenter.swift"), encoding: .utf8
        )
        #expect(presenter.contains("let window = MacMailAuxiliaryWindow("))
        #expect(compose.contains("sendAction: isSendButtonDisabled ? nil : performSendButtonAction"))
        #expect(compose.contains("Button(action: performSendButtonAction)"))
        #expect(compose.contains("isInteractionBlocked || (!canSend && pendingUndoSendTask == nil)"))
        #expect(compose.contains("guard !isSendButtonDisabled else { return }"))
        #expect(compose.contains("""
        if pendingUndoSendTask != nil {
                    cancelUndoSend()
                } else {
                    beginUndoSend {
                        await send()
        """))
    }

    @Test(
        "auxiliary presentations use standard resizable windows",
        arguments: [
            MailNavigationState.Sheet.compose,
            .profiles,
            .themePicker,
            .mailboxAssistant
        ]
    )
    func auxiliaryPresentationsUseStandardResizableWindows(
        sheet: MailNavigationState.Sheet
    ) {
        let configuration = MacMailAuxiliaryWindowConfiguration.configuration(for: sheet)

        #expect(configuration.styleMask.contains(.titled))
        #expect(configuration.styleMask.contains(.closable))
        #expect(configuration.styleMask.contains(.miniaturizable))
        #expect(configuration.styleMask.contains(.resizable))
        #expect(configuration.defaultSize.width >= configuration.minimumSize.width)
        #expect(configuration.defaultSize.height >= configuration.minimumSize.height)
        #expect(!configuration.title.isEmpty)
        #expect(!configuration.frameAutosaveName.isEmpty)
    }

    @Test("compose windows cannot restore to the cramped legacy popup size")
    func composeWindowsCannotRestoreToCrampedLegacyPopupSize() {
        let configuration = MacMailAuxiliaryWindowConfiguration.configuration(for: .compose)

        #expect(configuration.minimumSize.width >= 680)
        #expect(configuration.minimumSize.height >= 560)
        #expect(configuration.defaultSize.width >= 800)
        #expect(configuration.defaultSize.height >= 660)
    }

    @Test("compose windows use a unified toolbar and message title")
    func composeWindowsUseUnifiedToolbar() {
        let configuration = MacMailAuxiliaryWindowConfiguration.configuration(for: .compose)

        #expect(configuration.styleMask.contains(.fullSizeContentView))
        #expect(configuration.title == ComposePresentation.windowTitle(subject: ""))
        #expect(configuration.titleVisibility == .visible)
        #expect(configuration.titlebarAppearsTransparent)
        #expect(configuration.toolbarStyle == .unified)
        #expect(!configuration.isMovableByWindowBackground)
    }

    @Test("compose toolbar orders Send before format, attachment, and overflow")
    func composeToolbarOrderAndTitleFallback() {
        let configuration = MacMailAuxiliaryWindowConfiguration.configuration(for: .compose)

        #expect(MacComposeToolbarItemIdentifier.defaultOrder == [
            MacComposeToolbarItemIdentifier.send,
            .flexibleSpace,
            MacComposeToolbarItemIdentifier.format,
            MacComposeToolbarItemIdentifier.attachment,
            MacComposeToolbarItemIdentifier.more
        ])
        #expect(configuration.title == String(localized: "New Message", bundle: .module))
    }

    @Test("detached readers retain a descriptive title with utility chrome")
    @MainActor
    func detachedReadersMatchComposeWindowChrome() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: DetachedMessageWindowChrome.styleMask,
            backing: .buffered,
            defer: false
        )

        DetachedMessageWindowChrome.apply(to: window)

        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(window.titleVisibility == .visible)
        #expect(window.titlebarAppearsTransparent)
        #expect(window.titlebarSeparatorStyle == .none)
        #expect(window.toolbarStyle == .automatic)
    }

    @Test("first presentation activates the auxiliary window")
    func firstPresentationActivatesAuxiliaryWindow() {
        #expect(MacMailAuxiliaryWindowActivationPolicy.shouldActivate(
            hasWindow: false,
            activeSheet: nil,
            presentedSheet: .compose
        ))
    }

    @Test("switching auxiliary sheets activates the new window")
    func switchingAuxiliarySheetsActivatesNewWindow() {
        #expect(MacMailAuxiliaryWindowActivationPolicy.shouldActivate(
            hasWindow: true,
            activeSheet: .profiles,
            presentedSheet: .compose
        ))
    }

    @Test("refreshing the same auxiliary sheet does not reactivate Brev")
    func refreshingSameAuxiliarySheetDoesNotReactivateBrev() {
        #expect(!MacMailAuxiliaryWindowActivationPolicy.shouldActivate(
            hasWindow: true,
            activeSheet: .compose,
            presentedSheet: .compose
        ))
    }

    @Test("restored auxiliary window frames are clamped onto the visible screen")
    func restoredAuxiliaryWindowFramesAreClampedOntoVisibleScreen() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let restoredFrame = CGRect(x: 242, y: 898, width: 680, height: 592)

        let constrainedFrame = MacMailAuxiliaryWindowPlacementPolicy.constrainedFrame(
            restoredFrame,
            visibleFrame: visibleFrame
        )

        #expect(constrainedFrame.minX >= visibleFrame.minX + 24)
        #expect(constrainedFrame.maxX <= visibleFrame.maxX - 24)
        #expect(constrainedFrame.minY >= visibleFrame.minY + 24)
        #expect(constrainedFrame.maxY <= visibleFrame.maxY - 24)
        #expect(constrainedFrame.size == restoredFrame.size)
    }

    @Test("auxiliary window frames already inside the visible screen stay put")
    func auxiliaryWindowFramesAlreadyInsideVisibleScreenStayPut() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: 300, y: 150, width: 820, height: 700)

        #expect(MacMailAuxiliaryWindowPlacementPolicy.constrainedFrame(
            frame,
            visibleFrame: visibleFrame
        ) == frame)
    }
}

@MainActor
private final class ComposeAcceleratorFixture {
    let window: MacMailAuxiliaryWindow
    let host = NSHostingController(rootView: Color.clear)
    let delegate = MacComposeToolbarDelegate()
    let bridge: ComposeNativeToolbarContentView

    init(action: @escaping () -> Void) {
        window = MacMailAuxiliaryWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 700),
            styleMask: MacMailAuxiliaryWindowConfiguration.configuration(for: .compose).styleMask,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = host
        let toolbar = NSToolbar(identifier: "ComposeAcceleratorTest")
        toolbar.delegate = delegate
        window.toolbar = toolbar
        bridge = ComposeNativeToolbarContentView(items: [
            MacComposeToolbarItemIdentifier.send: AnyView(Button("Send", action: action))
        ], sendAction: action)
        host.view.addSubview(bridge)
    }

    func event(
        modifiers: NSEvent.ModifierFlags = .command,
        keyCode: UInt16 = 36,
        type: NSEvent.EventType = .keyDown,
        isRepeat: Bool = false,
        timestamp: TimeInterval = 1
    ) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: modifiers, timestamp: timestamp,
            windowNumber: window.windowNumber, context: nil,
            characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: isRepeat, keyCode: keyCode
        ))
    }
}
#endif
