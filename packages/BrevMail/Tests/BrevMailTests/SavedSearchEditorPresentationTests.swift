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
import BrevSettings
import Foundation
import Testing

@Suite("SavedSearchEditorPresentation")
struct SavedSearchEditorPresentationTests {
    @Test("common predicate toggles and sidebar visibility round trip")
    func commonPredicatesRoundTrip() {
        let existing = SmartMailbox(
            id: "common",
            name: "Priority mail",
            query: .init(
                text: "project",
                hasAttachment: true,
                isUnread: true,
                isStarred: true
            ),
            isEnabled: false
        )
        var state = SavedSearchEditorPresentation(editing: existing)

        #expect(state.hasAttachment)
        #expect(state.isUnread)
        #expect(state.isStarred)
        #expect(!state.isEnabled)

        state.isEnabled = true
        let built = state.makeSmartMailbox()
        #expect(built.query.hasAttachment == true)
        #expect(built.query.isUnread == true)
        #expect(built.query.isStarred == true)
        #expect(built.isEnabled)
    }

    @Test("valid when name and at least one predicate present")
    func validity() {
        var state = SavedSearchEditorPresentation(kind: .messageSearch)
        state.name = "  "
        #expect(state.isValid == false)
        state.name = "From Boss"
        #expect(state.isValid == false)
        state.fromText = "boss@example.com"
        #expect(state.isValid)

        state.fromText = ""
        state.isUnread = true
        #expect(state.isValid)
    }

    @Test("builds smart mailbox preserving id and isEnabled on edit")
    func buildsPreservingID() {
        let existing = SmartMailbox(id: "x", name: "Old", kind: .attachmentSearch,
                                    query: .init(text: "old"), isEnabled: true)
        var state = SavedSearchEditorPresentation(editing: existing)
        state.name = "New"
        state.queryText = "invoice"
        let built = state.makeSmartMailbox()
        #expect(built.id == "x")
        #expect(built.name == "New")
        #expect(built.kind == .attachmentSearch)
        #expect(built.isEnabled == true)
        #expect(built.query.text == "invoice")
    }

    @Test("edit state preserves disabled mailboxes")
    func buildsPreservingDisabledState() {
        let existing = SmartMailbox(id: "disabled", name: "Disabled", kind: .messageSearch,
                                    query: .init(text: "project"), isEnabled: false)
        let state = SavedSearchEditorPresentation(editing: existing)
        let built = state.makeSmartMailbox()
        #expect(built.id == "disabled")
        #expect(built.isEnabled == false)
    }

    @Test("attachment views discard message-only predicates")
    func attachmentViewsDiscardMessageOnlyPredicates() {
        var state = SavedSearchEditorPresentation(kind: .attachmentSearch)
        state.name = "Receipts"
        state.queryText = "invoice"
        state.fromText = "billing@example.com"
        state.toText = "me@example.com"
        state.isUnread = true
        state.isStarred = true

        let built = state.makeSmartMailbox()

        #expect(built.query.from == "billing@example.com")
        #expect(built.query.to == nil)
        #expect(built.query.isUnread == nil)
        #expect(built.query.isStarred == nil)
        #expect(built.query.hasAttachment == true)
    }

    @Test("new state generates an id and trims name; empty optional fields map to nil")
    func buildsNew() {
        var state = SavedSearchEditorPresentation(kind: .messageSearch)
        state.name = "  Receipts  "
        state.queryText = "  receipt  "
        state.fromText = ""
        state.toText = "  "
        let built = state.makeSmartMailbox()
        #expect(built.id.isEmpty == false)
        #expect(built.name == "Receipts")
        #expect(built.isEnabled == true)
        #expect(built.query.from == nil)
        #expect(built.query.to == nil)
        #expect(built.query.text == "receipt")
    }
}
