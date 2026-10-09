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
@testable import BrevMail
import Foundation
import SwiftUI
import Testing

@Suite("MessageListKeyboardNavigation")
@MainActor
struct MessageListKeyboardNavigationTests {
    @Test("bare list keys map to list commands")
    func bareKeysMapToCommands() {
        let expectations: [(KeyEquivalent, MessageListKeyCommand)] = [
            (.delete, .deleteSelection),
            (.deleteForward, .deleteSelection),
            (.escape, .clearSelection),
            (.home, .moveToStart),
            (.end, .moveToEnd),
            (.pageUp, .pageUp),
            (.pageDown, .pageDown),
        ]
        for (key, command) in expectations {
            #expect(MessageListKeyboardNavigation.command(for: key, modifiers: []) == command)
        }
    }

    @Test("system-added function and numeric-pad flags do not block navigation keys")
    func functionFlagsAreIgnored() {
        #expect(MessageListKeyboardNavigation.command(for: .home, modifiers: [.function]) == .moveToStart)
        #expect(MessageListKeyboardNavigation.command(for: .pageDown, modifiers: [.function, .numericPad]) == .pageDown)
    }

    @Test("modified keys are left to menu commands and the system")
    func modifiedKeysAreIgnored() {
        #expect(MessageListKeyboardNavigation.command(for: .delete, modifiers: [.command]) == nil)
        #expect(MessageListKeyboardNavigation.command(for: .delete, modifiers: [.shift]) == nil)
        #expect(MessageListKeyboardNavigation.command(for: .home, modifiers: [.option]) == nil)
        #expect(MessageListKeyboardNavigation.command(for: .escape, modifiers: [.control]) == nil)
    }

    @Test("unrelated keys have no command")
    func unrelatedKeysAreIgnored() {
        #expect(MessageListKeyboardNavigation.command(for: .return, modifiers: []) == nil)
        #expect(MessageListKeyboardNavigation.command(for: .upArrow, modifiers: []) == nil)
        #expect(MessageListKeyboardNavigation.command(for: "a", modifiers: []) == nil)
    }

    @Test("start and end jump to the first and last row")
    func startAndEndTargets() {
        #expect(MessageListKeyboardNavigation.targetIndex(for: .moveToStart, current: 7, count: 30) == 0)
        #expect(MessageListKeyboardNavigation.targetIndex(for: .moveToEnd, current: 7, count: 30) == 29)
        #expect(MessageListKeyboardNavigation.targetIndex(for: .moveToStart, current: nil, count: 30) == 0)
        #expect(MessageListKeyboardNavigation.targetIndex(for: .moveToEnd, current: nil, count: 30) == 29)
    }

    @Test("page keys move by the page step and clamp at both ends")
    func pageTargetsClamp() {
        let step = MessageListKeyboardNavigation.pageStep
        #expect(MessageListKeyboardNavigation.targetIndex(for: .pageDown, current: 2, count: 100) == 2 + step)
        #expect(MessageListKeyboardNavigation.targetIndex(for: .pageUp, current: 50, count: 100) == 50 - step)
        #expect(MessageListKeyboardNavigation.targetIndex(for: .pageDown, current: 95, count: 100) == 99)
        #expect(MessageListKeyboardNavigation.targetIndex(for: .pageUp, current: 3, count: 100) == 0)
    }

    @Test("page keys without a selection start at the first row")
    func pageWithoutSelectionStartsAtTop() {
        #expect(MessageListKeyboardNavigation.targetIndex(for: .pageDown, current: nil, count: 100) == 0)
        #expect(MessageListKeyboardNavigation.targetIndex(for: .pageUp, current: nil, count: 100) == 0)
    }

    @Test("an empty list has no target and non-movement commands have none either")
    func emptyAndNonMovementTargets() {
        #expect(MessageListKeyboardNavigation.targetIndex(for: .moveToEnd, current: nil, count: 0) == nil)
        #expect(MessageListKeyboardNavigation.targetIndex(for: .pageDown, current: 0, count: 0) == nil)
        #expect(MessageListKeyboardNavigation.targetIndex(for: .deleteSelection, current: 1, count: 5) == nil)
        #expect(MessageListKeyboardNavigation.targetIndex(for: .clearSelection, current: 1, count: 5) == nil)
    }

    @Test("navigation state applies movement commands to the loaded headers")
    func navigationStateMoves() {
        let headers = (0 ..< 25).map { Self.makeHeader(id: "m\($0)") }
        let state = MailNavigationState()
        state.selectMessage(headers[5], from: headers)

        state.moveSelection(.moveToEnd)
        #expect(state.selectedMessageID == "m24")
        state.moveSelection(.moveToStart)
        #expect(state.selectedMessageID == "m0")
        state.moveSelection(.pageDown)
        #expect(state.selectedMessageID == "m\(MessageListKeyboardNavigation.pageStep)")
        state.moveSelection(.pageUp)
        #expect(state.selectedMessageID == "m0")
    }

    @Test("movement commands on an empty list leave the selection empty")
    func navigationStateEmpty() {
        let state = MailNavigationState()
        state.moveSelection(.moveToEnd)
        #expect(state.selectedMessageID == nil)
    }

    @Test("non-movement commands do not change the selection")
    func navigationStateIgnoresNonMovement() {
        let headers = [Self.makeHeader(id: "a"), Self.makeHeader(id: "b")]
        let state = MailNavigationState()
        state.selectMessage(headers[1], from: headers)
        state.moveSelection(.deleteSelection)
        state.moveSelection(.clearSelection)
        #expect(state.selectedMessageID == "b")
    }

    private static func makeHeader(id: MessageHeader.ID) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: "thread-\(id)",
            folderID: "inbox",
            from: Correspondent(name: "Ada Lovelace", email: "ada@example.com"),
            to: [Correspondent(name: "Brev", email: "hello@brev.test")],
            subject: "Subject \(id)",
            snippet: "Snippet",
            date: Date(timeIntervalSince1970: 1_735_689_600)
        )
    }
}
