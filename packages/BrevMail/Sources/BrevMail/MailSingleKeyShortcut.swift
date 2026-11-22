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
import BrevSettings
import Foundation

/// Bare-key mail actions for a focused macOS message list (#300).
enum MailSingleKeyShortcut: String {
    case next = "j"
    case previous = "k"
    case archive = "e"
    case reply = "r"
    case star = "s"
    case delete = "#"
    case snooze = "h"

    /// The row action the key performs; navigation keys have none.
    var menuAction: MessageContextMenuAction? {
        switch self {
        case .next, .previous: nil
        case .archive: .archive
        case .reply: .reply
        case .star: .toggleFlag
        case .delete: .delete
        case .snooze: .toggleSnooze
        }
    }

    /// The key as printed on the keycap.
    var keyLabel: String { rawValue.uppercased() }

    static var legend: String {
        String(
            localized: "In the message list or reader: J next · K previous · E archive · R reply · S star · # delete · H snooze.",
            bundle: .module
        )
    }

    /// Tooltip text naming the key, or the plain title when single keys are off.
    func help(_ title: String, enabled: Bool) -> String {
        guard enabled else { return title }
        return String(localized: "\(title) (\(keyLabel))", bundle: .module)
    }
}

#if os(macOS)
import AppKit
import SwiftUI
import WebKit

extension MailSingleKeyShortcut {
    /// Embedded readers act only on the live selection in the same source.
    /// A detached reader has a fixed message and no adjacent-message context.
    @MainActor
    func performInReader(
        navigation: MailNavigationState?, header: MessageHeader?, sourceID: MailSourceID?,
        perform: (MessageContextMenuAction, MessageHeader) -> Bool
    ) -> Bool {
        guard let header else { return false }
        if let navigation {
            guard navigation.selectedSourceID == sourceID, navigation.selectedMessageID == header.id,
                  navigation.presentedSheet == nil, navigation.bulkSelection.isEmpty else { return false }
        }
        if let menuAction { return perform(menuAction, header) }
        guard let navigation else { return false }
        if self == .previous { navigation.selectPreviousHeader() } else { navigation.selectNextHeader() }
        return true
    }

    /// Matches the produced character. Modifier shortcuts belong to menus.
    static func match(_ characters: String, modifiers: NSEvent.ModifierFlags) -> Self? {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        // Match the character produced by the current keyboard layout. Some
        // layouts use Shift for "#", others use Option. Never guess from "3".
        if characters == "#", flags.subtracting([.shift, .option]).isEmpty { return .delete }
        guard flags.isEmpty else { return nil }
        // Caps Lock yields uppercase letters with no Shift; treat them as bare keys.
        return Self(rawValue: characters.lowercased())
    }

    /// Resolves a key-down event only when a mail pane, not a text input, owns it.
    @MainActor
    static func resolve(_ event: NSEvent?, window: NSWindow?, enabled: Bool, focused: Bool) -> Self? {
        guard enabled, focused, let window, let event, event.type == .keyDown, !event.isARepeat,
              event.windowNumber == window.windowNumber, window.attachedSheet == nil,
              let responder = window.firstResponder, !(responder is NSText), !(responder is NSTextField),
              let characters = event.characters else { return nil }
        var view = responder as? NSView
        while let current = view {
            // Embedded web content owns keyboard events, including editable content.
            if current is WKWebView { return nil }
            view = current.superview
        }
        return match(characters, modifiers: event.modifierFlags)
    }
}

/// Routes resolved single-key presses from a focused pane to its row actions.
struct MailSingleKeyShortcutModifier: ViewModifier {
    @AppStorage(MailKeyboardPreferences.singleKeyShortcuts) private var enabled = true
    let focused: Bool
    let perform: (MailSingleKeyShortcut) -> Bool

    func body(content: Content) -> some View {
        content.onKeyPress(phases: .down) { _ in
            guard let command = MailSingleKeyShortcut.resolve(
                NSApp.currentEvent, window: NSApp.keyWindow, enabled: enabled, focused: focused
            ) else { return .ignored }
            return perform(command) ? .handled : .ignored
        }
    }
}

/// Gives the reader its own Tab stop without claiming focus from the list or its editors.
struct ReaderSingleKeyShortcutModifier: ViewModifier {
    @FocusState private var focused: Bool
    let perform: (MailSingleKeyShortcut) -> Bool

    func body(content: Content) -> some View {
        content.focusable()
            .focused($focused)
            .focusEffectDisabled()
            .modifier(MailSingleKeyShortcutModifier(focused: focused, perform: perform))
    }
}
#endif
