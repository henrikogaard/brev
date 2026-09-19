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
@testable import BrevMail
import Foundation
import Testing

@Suite("Compose body selection")
struct ComposeBodySelectionTests {
    @Test("selection snapshot captures selected text from UTF-16 ranges")
    func selectionSnapshotCapturesSelectedTextFromUTF16Ranges() throws {
        let body = "Hello Henrik, ship Brev."
        let range = (body as NSString).range(of: "Henrik")

        let selection = try #require(ComposeBodyTextSelection(bodyText: body, nsRange: range))

        #expect(selection.selectedText == "Henrik")
        #expect(selection.nsRange == range)
        #expect(ComposeBodyTextSelection(bodyText: body, nsRange: NSRange(location: range.location, length: 0)) == nil)
        #expect(ComposeBodyTextSelection(bodyText: body, nsRange: NSRange(location: 999, length: 3)) == nil)
    }

    @Test("selection snapshot from the live character buffer matches bodyText init")
    func selectionFromCharactersMatchesBodyTextInit() throws {
        let body = "Hello Henrik, ship Brev."
        let characters = body as NSString
        let range = characters.range(of: "Henrik")

        let fromCharacters = try #require(ComposeBodyTextSelection(
            characters: characters,
            nsRange: range
        ))
        let fromBodyText = try #require(ComposeBodyTextSelection(
            bodyText: body,
            nsRange: range
        ))

        #expect(fromCharacters == fromBodyText)
        #expect(ComposeBodyTextSelection(
            characters: characters,
            nsRange: NSRange(location: range.location, length: 0)
        ) == nil)
        #expect(ComposeBodyTextSelection(
            characters: characters,
            nsRange: NSRange(location: 999, length: 3)
        ) == nil)
        // Whitespace-only selections stay nil, matching the String init.
        #expect(ComposeBodyTextSelection(
            characters: characters,
            nsRange: characters.range(of: " ")
        ) == nil)
    }

    @Test("insertion point validates against a character count")
    func insertionPointValidatesAgainstCharacterCount() throws {
        let body = "Draft body"
        let characters = body as NSString

        let insertionPoint = try #require(ComposeBodyInsertionPoint(
            characterCount: characters.length,
            nsRange: NSRange(location: 5, length: 0)
        ))
        #expect(insertionPoint.nsRange == NSRange(location: 5, length: 0))
        // Caret at end-of-document stays valid, just like `Range(_:in:)`.
        #expect(ComposeBodyInsertionPoint(
            characterCount: characters.length,
            nsRange: NSRange(location: characters.length, length: 0)
        ) != nil)
        #expect(ComposeBodyInsertionPoint(
            characterCount: characters.length,
            nsRange: NSRange(location: characters.length + 1, length: 0)
        ) == nil)
        #expect(ComposeBodyInsertionPoint(
            characterCount: characters.length,
            nsRange: NSRange(location: 0, length: 2)
        ) == nil)
    }

    @Test("selected-text shortcut request uses only selected text")
    func selectedTextShortcutRequestUsesOnlySelectedText() throws {
        let body = "Please ship Brev today."
        let selection = try #require(ComposeBodyTextSelection(
            bodyText: body,
            nsRange: (body as NSString).range(of: "ship Brev")
        ))

        let request = ComposeAIShortcutRequest(
            action: .formal,
            bodyText: body,
            target: .selection(selection)
        )

        #expect(request.inputText == "ship Brev")
        #expect(request.bodyTextSnapshot == body)
        #expect(request.target == .selection(selection))
    }

    @Test("selected-text response replaces only the original selected range")
    func selectedTextResponseReplacesOnlyOriginalSelectedRange() throws {
        let body = "Please ship Brev today."
        let selection = try #require(ComposeBodyTextSelection(
            bodyText: body,
            nsRange: (body as NSString).range(of: "ship Brev")
        ))
        let request = ComposeAIShortcutRequest(
            action: .formal,
            bodyText: body,
            target: .selection(selection)
        )

        let updated = ComposeAIShortcutResponsePolicy.appliedText(
            for: request,
            activeRequest: request,
            currentBodyText: body,
            currentSelection: selection,
            responseText: "send Brev"
        )

        #expect(updated == "Please send Brev today.")
    }

    @Test("selected-text response rejects stale body or changed selection")
    func selectedTextResponseRejectsStaleBodyOrChangedSelection() throws {
        let body = "Please ship Brev today."
        let selection = try #require(ComposeBodyTextSelection(
            bodyText: body,
            nsRange: (body as NSString).range(of: "ship Brev")
        ))
        let changedSelection = try #require(ComposeBodyTextSelection(
            bodyText: body,
            nsRange: (body as NSString).range(of: "today")
        ))
        let request = ComposeAIShortcutRequest(
            action: .formal,
            bodyText: body,
            target: .selection(selection)
        )

        #expect(!ComposeAIShortcutResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentBodyText: "Please ship Brev tomorrow.",
            currentSelection: selection
        ))
        #expect(!ComposeAIShortcutResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: request,
            currentBodyText: body,
            currentSelection: changedSelection
        ))
        #expect(ComposeAIShortcutResponsePolicy.appliedText(
            for: request,
            activeRequest: request,
            currentBodyText: body,
            currentSelection: changedSelection,
            responseText: "send Brev"
        ) == nil)
    }
}
