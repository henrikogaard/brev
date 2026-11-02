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

@Suite("Navigation projection acceptance")
@MainActor
struct NavigationSelectionAcceptanceTests {
    @Test("same IDs in another source cannot reuse workflow membership")
    func sourceAndFolderChange() {
        let fixture = NavigationSelectionAcceptanceFixture(count: 6)
        defer { fixture.cleanup() }
        fixture.configureWorkflow()
        fixture.workflowState = LocalMessageWorkflowStatePolicy.markingDone(
            fixture.headers.map { SourceMessageID(sourceID: fixture.sourceID, messageID: $0.id) },
            now: Date(), in: fixture.workflowState
        )
        #expect(fixture.selectionHeaders().isEmpty)
        fixture.sourceID = MailSourceID(accountID: "other", mailboxID: "mailbox")
        fixture.navigation.selectFolder("other-folder", in: fixture.sourceID)
        #expect(fixture.navigation.selectedHeader == nil)
        #expect(fixture.selectionHeaders().count == 6)
        #expect(fixture.builds == 2)
        fixture.replaceHeader(at: 0, folderID: "other-folder")
        fixture.navigation.selectMessage(fixture.headers[0], in: fixture.sourceID, headers: fixture.selectionHeaders())
        #expect(fixture.navigation.selectedHeader?.folderID == "other-folder")
        #expect(fixture.navigation.selectedSourceID == fixture.sourceID)
        #expect(fixture.builds == 3)
    }

    @Test("selected disappearance drops cached indexes and retained reply context")
    func selectedDisappearance() {
        let fixture = NavigationSelectionAcceptanceFixture(count: 6)
        defer { fixture.cleanup() }
        let selected = fixture.headers[1]
        fixture.navigation.selectMessage(selected, from: fixture.selectionHeaders())
        #expect(fixture.navigation.selectedHeader == selected)
        fixture.headers.removeAll { $0.id == selected.id }
        let changed = fixture.presentation()
        fixture.navigation.currentFolderHeaders = changed.navigationHeaders
        #expect(fixture.navigation.selectedHeader == nil)
        #expect(changed.headersByThreadID[selected.threadID]?.contains { $0.id == selected.id } == false)
        #expect(fixture.builds == 2)
    }

    @Test("same-ID content refresh invalidates projections without changing selection")
    func contentRefresh() {
        let fixture = NavigationSelectionAcceptanceFixture(count: 6)
        defer { fixture.cleanup() }
        let first = fixture.presentation()
        fixture.navigation.selectMessage(fixture.headers[0], from: first.navigationHeaders)
        fixture.replaceHeader(at: 0, subject: "Updated subject", snippet: "New body-derived preview")
        let changed = fixture.presentation()
        fixture.navigation.selectMessage(fixture.headers[0], from: changed.navigationHeaders)
        #expect(fixture.navigation.selectedHeader?.snippet == "New body-derived preview")
        #expect(changed.headers.first?.subject == "Updated subject")
        #expect(first.headers.first?.snippet == "Synthetic preview")
        #expect(!changed.navigationHeaders.sharesRetainedBuffer(with: first.navigationHeaders))
        #expect(fixture.builds == 2)
        #expect(fixture.selectionHeaders().sharesRetainedBuffer(with: changed.navigationHeaders))
        #expect(fixture.builds == 2)
    }

    @Test("body-only changes render fresh content while retaining header projection")
    func bodyRefresh() async {
        let fixture = NavigationSelectionAcceptanceFixture(count: 6)
        defer { fixture.cleanup() }
        let projected = fixture.selectionHeaders()
        let selected = fixture.headers[0]
        fixture.navigation.selectMessage(selected, from: projected)
        let renderer = BodyRenderer()
        let old = await renderer.render(MessageBody(messageID: selected.id, html: "<p>Before</p>", plainText: "Before"))
        let updated = await renderer.render(MessageBody(messageID: selected.id, html: "<p>After</p>", plainText: "After"))
        #expect(old.plainText == "Before")
        #expect(updated.plainText == "After")
        #expect(updated.html == "<p>After</p>")
        #expect(fixture.selectionHeaders().sharesRetainedBuffer(with: projected))
        #expect(fixture.navigation.selectedHeader == selected)
        #expect(fixture.builds == 1)
    }
}
