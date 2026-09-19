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

#if os(macOS)
import AppKit
import BrevBackend
@testable import BrevMail
import Observation
import SwiftUI
import Testing

@Suite("Workflow navigation reconciliation", .serialized)
@MainActor
struct WorkflowNavigationReconciliationTests {
    @Observable
    final class Model {
        var workflow = LocalMessageWorkflowState.defaults
    }

    struct Harness: View {
        @Bindable var model: Model
        let navigation: MailNavigationState
        let backend: MockBackend
        let folder: Folder
        let source: MailSourceID
        let unified: Bool

        var body: some View {
            if unified {
                UnifiedInboxListView(
                    navigation: navigation, backends: [backend],
                    sourceSections: [MailSourceSection(
                        id: source, account: backend.account,
                        mailbox: Mailbox(
                            id: source.mailboxID,
                            email: "fixture@example.org",
                            displayName: "Fixture",
                            isPrimary: true
                        ),
                        folders: [folder]
                    )],
                    localMessageWorkflowState: $model.workflow, isWorkBlocked: false,
                    composeActions: MailComposePresentationActions(
                        newMessage: {}, reply: { _ in }, replyAll: { _ in }, forward: { _ in }
                    )
                )
            } else {
                MessageListView(
                    navigation: navigation, backend: backend, sourceID: source,
                    folder: folder, allFolders: [folder],
                    localMessageWorkflowState: $model.workflow,
                    composeActions: MailComposePresentationActions(
                        newMessage: {}, reply: { _ in }, replyAll: { _ in }, forward: { _ in }
                    )
                )
            }
        }
    }

    @Test("external workflow changes and undo update reader membership without a reload", arguments: [false, true], [false, true])
    func externalWorkflowChange(unified: Bool, snooze: Bool) async throws {
        let folder = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let headers = ["a", "b", "c"].enumerated().map { index, id in
            MessageHeader(id: id, threadID: id, folderID: folder.id,
                          from: Correspondent(email: "fixture@example.org"),
                          subject: id, snippet: "", date: Date(timeIntervalSince1970: Double(300 - index)))
        }
        let backend = MockBackend(capabilities: [], folders: [folder], messagesByFolder: [folder.id: headers])
        let source = MailSourceID(accountID: backend.account.id, mailboxID: backend.account.id)
        let navigation = MailNavigationState()
        navigation.selectedFolderID = folder.id
        navigation.selectedSourceID = source
        let model = Model()
        let host = NSHostingView(rootView: Harness(model: model, navigation: navigation,
                                                   backend: backend, folder: folder, source: source, unified: unified))
        host.frame = CGRect(x: 0, y: 0, width: 600, height: 600)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        window.orderFront(nil)
        for _ in 0 ..< 100 where navigation.currentFolderHeaders.count != 3 {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(navigation.currentFolderHeaders.map(\.id) == ["a", "b", "c"])
        navigation.selectedMessageID = "b"
        let messageID = SourceMessageID(sourceID: source, messageID: "b")
        let previousState = model.workflow
        let undo = UndoQueue()
        undo.push(UndoableMutation(description: "Restore workflow") {
            await MainActor.run { model.workflow = previousState }
        })
        model.workflow = snooze
            ? LocalMessageWorkflowStatePolicy.snoozing(messageID, until: .distantFuture, in: .defaults)
            : LocalMessageWorkflowStatePolicy.markingDone([messageID], in: .defaults)
        for _ in 0 ..< 50 where navigation.currentFolderHeaders.count != 2 {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(navigation.currentFolderHeaders.map(\.id) == ["a", "c"])
        #expect(navigation.selectedMessageID == "c")
        let task = try #require(undo.undo())
        #expect(await task.value)
        for _ in 0 ..< 50 where navigation.currentFolderHeaders.count != 3 {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(navigation.currentFolderHeaders.map(\.id) == ["a", "b", "c"])
        #expect(navigation.selectedMessageID == "c")
    }
}
#endif
