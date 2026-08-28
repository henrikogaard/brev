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
import Testing

@Suite("MacMailAuxiliaryWindowConfiguration")
struct MacMailAuxiliaryWindowConfigurationTests {
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

    @Test("compose windows use full-size content with an inset custom toolbar")
    func composeWindowsUseFullSizeContentWithInsetCustomToolbar() {
        let configuration = MacMailAuxiliaryWindowConfiguration.configuration(for: .compose)

        #expect(configuration.styleMask.contains(.fullSizeContentView))
        #expect(configuration.titleVisibility == .hidden)
        #expect(configuration.titlebarAppearsTransparent)
        #expect(configuration.toolbarStyle == .automatic)
        #expect(!configuration.isMovableByWindowBackground)
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
#endif
