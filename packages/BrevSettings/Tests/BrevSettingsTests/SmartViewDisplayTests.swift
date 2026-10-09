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

@testable import BrevSettings
import Foundation
import Testing

@Suite("Smart View display settings")
struct SmartViewDisplayTests {
    @Test("custom and built-in views move together and hidden positions survive reload")
    func mixedOrder() throws {
        var settings = SmartMailboxSettings(mailboxes: [
            .init(id: "custom", name: "Invoices", query: .init(text: "invoice"), isEnabled: true)
        ])
        settings.moveEntry(id: "custom:custom", by: -6)
        #expect(settings.orderedEntries.first?.id == "custom:custom")
        let first = try #require(settings.orderedEntries.first)
        settings.setEntry(first, isEnabled: false)
        settings.showInSidebar = false
        let restored = try JSONDecoder().decode(SmartMailboxSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored.orderedEntries.first?.id == "custom:custom")
        #expect(restored.orderedEntries.first?.isEnabled == false)
        #expect(!restored.showInSidebar)
    }

    @Test("legacy settings show the section and stale order IDs do not duplicate rows")
    func legacyDefaults() throws {
        var settings = try JSONDecoder().decode(SmartMailboxSettings.self, from: Data(#"{"mailboxes":[]}"#.utf8))
        #expect(settings.showInSidebar)
        settings.displayOrder = ["removed", "builtin:vip", "builtin:vip"]
        #expect(settings.orderedEntries.first?.id == "builtin:vip")
        #expect(settings.orderedEntries.count == 6)
    }

    @Test("dragging a row to a new position reorders entries, as List.onMove reports it")
    func dragReorder() {
        var settings = SmartMailboxSettings(mailboxes: [
            .init(id: "custom", name: "Invoices", query: .init(text: "invoice"), isEnabled: true)
        ])
        let before = settings.orderedEntries.map(\.id)
        // List.onMove reports the destination as an index in the original order.
        settings.moveEntries(from: IndexSet(integer: 0), to: 3)
        var expected = before
        let moved = expected.remove(at: 0)
        expected.insert(moved, at: 2)
        #expect(settings.orderedEntries.map(\.id) == expected)

        settings.moveEntries(from: IndexSet(integer: 4), to: 0)
        #expect(settings.orderedEntries.first?.id == expected[4])
        #expect(settings.orderedEntries.count == before.count)
    }
}
