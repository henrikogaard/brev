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

@Suite("SavedSearchSidebarPresentation")
struct SavedSearchSidebarPresentationTests {
    @Test("maps enabled saved searches to rows preserving order and kind icon")
    func mapsRows() {
        let mailboxes = [
            SmartMailbox(id: "a", name: "Invoices", kind: .attachmentSearch,
                         query: .init(text: "invoice"), isEnabled: true),
            SmartMailbox(id: "b", name: "From Boss", kind: .messageSearch,
                         query: .init(text: "", from: "boss@example.com"), isEnabled: true)
        ]
        let rows = SavedSearchSidebarPresentation.rows(from: mailboxes)
        #expect(rows.map(\.id) == ["a", "b"])
        #expect(rows[0].title == "Invoices")
        #expect(rows[0].symbolName == "paperclip")
        #expect(rows[1].symbolName == "magnifyingglass")
    }

    @Test("omits disabled saved searches")
    func omitsDisabled() {
        let mailboxes = [
            SmartMailbox(id: "a", name: "Off", kind: .messageSearch,
                         query: .init(text: "x"), isEnabled: false)
        ]
        #expect(SavedSearchSidebarPresentation.rows(from: mailboxes).isEmpty)
    }

    @Test("leaves a selected custom view after it is hidden or deleted")
    func leavesUnavailableSelection() {
        let enabled = SmartMailbox(
            id: "selected",
            name: "Selected",
            query: .init(text: "project"),
            isEnabled: true
        )
        var disabled = enabled
        disabled.isEnabled = false

        #expect(!SavedSearchSidebarPresentation.shouldLeaveSelection(
            selectedID: enabled.id,
            mailboxes: [enabled]
        ))
        #expect(SavedSearchSidebarPresentation.shouldLeaveSelection(
            selectedID: disabled.id,
            mailboxes: [disabled]
        ))
        #expect(SavedSearchSidebarPresentation.shouldLeaveSelection(
            selectedID: enabled.id,
            mailboxes: []
        ))
        #expect(!SavedSearchSidebarPresentation.shouldLeaveSelection(
            selectedID: nil,
            mailboxes: []
        ))
    }
}
