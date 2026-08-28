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
import Testing

@Suite("MessageLabelPresentation")
struct MessageLabelPresentationTests {
    @Test("display labels drop system labels and keep server order")
    func displayLabelsDropSystemLabels() {
        let labels = MessageLabelPresentation.displayLabels(
            from: ["\\Inbox", "Work", "\\Important", "Receipts/2026", "\\Starred"]
        )
        #expect(labels == ["Work", "Receipts/2026"])
    }

    @Test("row chips cap the visible count and report the overflow")
    func rowChipsCapVisibleCount() {
        let chips = MessageLabelPresentation.rowChips(
            from: ["A", "B", "C", "D", "\\Inbox"],
            limit: 2
        )
        #expect(chips.visible == ["A", "B"])
        #expect(chips.overflowCount == 2)

        let few = MessageLabelPresentation.rowChips(from: ["A"], limit: 2)
        #expect(few.visible == ["A"])
        #expect(few.overflowCount == 0)
    }

    @Test("candidate labels come from custom folders outside the Gmail system tree")
    func candidateLabelsFromFolders() {
        let folders = [
            Folder(id: "INBOX", name: "Inbox", role: .inbox),
            Folder(id: "[Gmail]/All Mail", name: "All Mail", role: .allMail),
            Folder(id: "[Gmail]/Custom", name: "Custom", role: .custom),
            Folder(id: "Work", name: "Work", role: .custom),
            Folder(id: "Work/Clients", name: "Clients", role: .custom, parentID: "Work"),
            Folder(id: "archive", name: "archive", role: .custom),
        ]
        #expect(MessageLabelPresentation.candidateLabels(from: folders) == ["archive", "Work", "Work/Clients"])
    }
}
