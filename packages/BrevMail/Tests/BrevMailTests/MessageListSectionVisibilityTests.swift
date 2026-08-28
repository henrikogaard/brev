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
import Testing

@Suite("MessageListSectionVisibility")
struct MessageListSectionVisibilityTests {
    @Test("collapsed sections keep their header and hide their rows")
    func collapsedSectionsKeepTheirHeaderAndHideTheirRows() {
        let today = Self.makeHeader(id: "today")
        let yesterday = Self.makeHeader(id: "yesterday")
        let sections = [
            MessageListDateSection(title: "Today", headers: [today]),
            MessageListDateSection(title: "Yesterday", headers: [yesterday])
        ]

        let visibleSections = MessageListSectionVisibility.sections(
            from: sections,
            collapsedIDs: ["Today"]
        )

        #expect(visibleSections.map(\.title) == ["Today", "Yesterday"])
        #expect(visibleSections.map(\.totalCount) == [1, 1])
        #expect(visibleSections.map(\.isCollapsed) == [true, false])
        #expect(visibleSections.map { $0.visibleHeaders.map(\.id) } == [[], ["yesterday"]])
    }

    private static func makeHeader(id: String) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: id,
            folderID: "inbox",
            from: Correspondent(name: "Ada", email: "ada@example.org"),
            subject: id,
            snippet: "",
            date: Date()
        )
    }
}
