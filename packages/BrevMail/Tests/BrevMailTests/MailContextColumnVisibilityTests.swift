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

@testable import BrevMail
import SwiftUI
import Testing

@Suite("MailContextColumnVisibility")
struct MailContextColumnVisibilityTests {
    @Test("mail context width on macOS matches inspector budgets")
    func mailContextWidthOnMacOS() {
        let width = MailPaneColumnWidthPolicy.mailContext(platform: MailPanePlatform.macOS)
        #expect(width?.minimum == 280)
        #expect(width?.ideal == 320)
        #expect(width?.maximum == 420)
    }

    @Test("mail context width is nil on iPhone")
    func mailContextWidthNilOnIPhone() {
        #expect(MailPaneColumnWidthPolicy.mailContext(platform: MailPanePlatform.iPhone) == nil)
    }

    @Test("mail context width is nil on iPad")
    func mailContextWidthNilOnIPad() {
        #expect(MailPaneColumnWidthPolicy.mailContext(platform: MailPanePlatform.iPad) == nil)
    }

    @Test("keyboard shortcut chord is command-option-i")
    func keyboardShortcutChord() {
        #expect(MailContextColumnVisibility.keyboardShortcutKey == "i")
        #expect(MailContextColumnVisibility.keyboardShortcutModifiers == EventModifiers.command.union(.option))
    }

    @Test("AI Sidebar command label reflects inspector visibility")
    func aiSidebarCommandLabelReflectsInspectorVisibility() {
        let hidden = MailContextColumnAction(isPresented: false) {}
        let shown = MailContextColumnAction(isPresented: true) {}

        #expect(hidden.label == MailContextColumnVisibility.toolbarLabel)
        #expect(hidden.label == "AI Sidebar")
        #expect(shown.label == "Hide AI Sidebar")
        // The column prints `toolbarLabel` at its own top, so the idle panel
        // below it has to name the missing state instead of repeating it.
        #expect(MailContextColumnVisibility.idleTitle == "No message selected")
        #expect(MailContextColumnVisibility.idleTitle != MailContextColumnVisibility.toolbarLabel)
        #expect(MailContextColumnVisibility.toolbarSymbolName == "sparkles")
    }

    #if os(macOS)
    @Test("AI Sidebar starts with room for sender context")
    func aiSidebarDefaultSenderContextHeight() {
        #expect(MailContextPanelSplitPolicy.defaultSenderHeight == 240)
    }
    #endif

    @MainActor
    @Test("mail context command toggle respects availability")
    func mailContextCommandToggleRespectsAvailability() {
        var invocations = 0
        let available = MailContextColumnAction(isAvailable: true) {
            invocations += 1
        }
        let blocked = MailContextColumnAction(isAvailable: false) {
            invocations += 1
        }

        available.toggle()
        blocked.toggle()

        #expect(invocations == 1)
    }
}
