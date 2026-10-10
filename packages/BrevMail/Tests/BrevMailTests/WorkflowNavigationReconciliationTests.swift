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
    @MainActor
    final class Model {
        var workflow = LocalMessageWorkflowState.defaults

        /// Workflow state the hosted view tree last rendered. The header count
        /// cannot stand in for it: a second startup load can still be in
        /// flight, and it filters with the live binding before SwiftUI has
        /// rendered the change. Undoing at that point puts the state back
        /// before the list ever saw it, so its `onChange` never fires.
        @ObservationIgnored private var renderedWorkflow = LocalMessageWorkflowState.defaults
        @ObservationIgnored private var renderWaiter: (
            workflow: LocalMessageWorkflowState, continuation: CheckedContinuation<Void, Never>
        )?

        func didRender(_ workflow: LocalMessageWorkflowState) {
            renderedWorkflow = workflow
            guard let waiter = renderWaiter, waiter.workflow == workflow else { return }
            renderWaiter = nil
            waiter.continuation.resume()
        }

        /// Suspends until the view tree has rendered `workflow`; the list's own
        /// `onChange` reconciliation runs in that same SwiftUI update.
        ///
        /// Returns early when the task is cancelled, so a render that never
        /// arrives ends at the test's time limit (which cancels the task) and
        /// fails on the assertions that follow instead of hanging the suite.
        func rendered(_ workflow: LocalMessageWorkflowState) async {
            guard renderedWorkflow != workflow else { return }
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    guard !Task.isCancelled else { return continuation.resume() }
                    renderWaiter = (workflow, continuation)
                }
            } onCancel: {
                Task { @MainActor in self.abandonRenderWait() }
            }
        }

        private func abandonRenderWait() {
            guard let waiter = renderWaiter else { return }
            renderWaiter = nil
            waiter.continuation.resume()
        }
    }

    struct Harness: View {
        @Bindable var model: Model
        let navigation: MailNavigationState
        let backend: MockBackend
        let folder: Folder
        let source: MailSourceID
        let unified: Bool

        var body: some View {
            list.onChange(of: model.workflow) { _, workflow in model.didRender(workflow) }
        }

        @ViewBuilder private var list: some View {
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

    @Test(
        "external workflow changes and undo update reader membership without a reload",
        .timeLimit(.minutes(1)),
        arguments: [false, true], [false, true]
    )
    func externalWorkflowChange(unified: Bool, snooze: Bool) async throws {
        try await exerciseWorkflowChange(unified: unified, snooze: snooze, unreadOnly: false)
    }

    @Test("unified workflow changes keep selection inside the visible unread filter", .timeLimit(.minutes(1)))
    func filteredUnifiedWorkflowChange() async throws {
        try await exerciseWorkflowChange(unified: true, snooze: false, unreadOnly: true)
    }

    private func exerciseWorkflowChange(unified: Bool, snooze: Bool, unreadOnly: Bool) async throws {
        let folder = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let headers = ["a", "b", "c"].enumerated().map { index, id in
            MessageHeader(id: id, threadID: id, folderID: folder.id,
                          from: Correspondent(email: "fixture@example.org"),
                          subject: id, snippet: "", date: Date(timeIntervalSince1970: Double(300 - index)),
                          isRead: unreadOnly && id == "c")
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
        if unreadOnly { navigation.mailboxFilter = MailboxFilterQuery(activeFilters: [.unread]) }
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
        await model.rendered(model.workflow)
        #expect(navigation.currentFolderHeaders.map(\.id) == (unreadOnly ? ["a"] : ["a", "c"]))
        #expect(navigation.selectedMessageID == (unreadOnly ? "a" : "c"))
        let task = try #require(undo.undo())
        #expect(await task.value)
        await model.rendered(previousState)
        #expect(navigation.currentFolderHeaders.map(\.id) == (unreadOnly ? ["a", "b"] : ["a", "b", "c"]))
        #expect(navigation.selectedMessageID == (unreadOnly ? "a" : "c"))
    }
}
#endif
