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

@Suite("Progressive mail search")
struct MailSearchProgressTests {
    let source = MailSourceID(accountID: "a", mailboxID: "a")
    let other = MailSourceID(accountID: "b", mailboxID: "b")

    @MainActor
    @Test("a new search worker cancels and replaces the previous request")
    func workerReplacementCancelsPrevious() async {
        let worker = MailSearchTaskOwner()
        let started = SearchWorkerSignal()
        var canceled = false
        var completed = false
        let first = Task {
            await worker.run {
                await started.signal()
                do { try await Task.sleep(nanoseconds: 30_000_000_000) }
                catch { canceled = true }
            }
        }
        await started.wait()
        await worker.run { completed = true }
        await first.value
        #expect(canceled)
        #expect(completed)
    }

    @Test("retry waits until other mailbox searches settle")
    func retryWaitsForOtherSources() {
        var state = MailSearchProgressState()
        let request = state.begin(sources: [source, other])
        state.fail(source: source, request: request)
        #expect(!state.canRetry)
        state.apply(MailSearchUpdate(headers: [], coverage: .server, isComplete: true), source: other, request: request)
        #expect(state.canRetry)
    }

    @Test("attachment match names merge per source and reset on replacement")
    func attachmentMatchNames() {
        var state = MailSearchProgressState()
        let request = state.begin(sources: [source])
        state.apply(
            MailSearchUpdate(
                headers: [header("hit", 1)],
                coverage: .cached,
                attachmentMatchNames: ["hit": "invoice.pdf"]
            ),
            source: source,
            request: request
        )
        #expect(state.matchedAttachmentName(for: "hit", source: source) == "invoice.pdf")
        #expect(state.matchedAttachmentName(for: "hit", source: other) == nil)
        #expect(state.matchedAttachmentName(for: "miss", source: source) == nil)

        // A replacing update clears names carried by the previous page.
        state.apply(
            MailSearchUpdate(
                headers: [header("hit", 1)],
                coverage: .server,
                replacesResults: true
            ),
            source: source,
            request: request
        )
        #expect(state.matchedAttachmentName(for: "hit", source: source) == nil)
    }

    @Test("finishing an interrupted request settles progress without affecting newer requests")
    func interruptedRequestSettles() {
        var state = MailSearchProgressState()
        let old = state.begin(sources: [source])
        let current = state.begin(sources: [source])
        state.finish(request: old)
        #expect(state.isSearching)
        #expect(!state.hasFailure)
        state.finish(request: current)
        #expect(!state.isSearching)
        #expect(state.hasFailure)
    }

    @Test("server pages replace provisional cache and retain source-qualified duplicates")
    func serverPagesReplaceCache() {
        var state = MailSearchProgressState()
        let request = state.begin(sources: [source, other])
        let applied1 = state.apply(
            MailSearchUpdate(headers: [header("cached", 1)], coverage: .cached),
            source: source,
            request: request
        )
        #expect(applied1)
        let applied2 = state.apply(
            MailSearchUpdate(headers: [header("same", 3)], coverage: .server),
            source: source,
            request: request
        )
        #expect(applied2)
        let applied3 = state.apply(
            MailSearchUpdate(headers: [header("older", 2), header("same", 3)], coverage: .server),
            source: source,
            request: request
        )
        #expect(applied3)
        let applied4 = state.apply(
            MailSearchUpdate(headers: [header("same", 1)], coverage: .cached, isComplete: true),
            source: other,
            request: request
        )
        #expect(applied4)
        #expect(state.headers(for: source).map(\.id) == ["same", "older"])
        #expect(state.headers(for: other).map(\.id) == ["same"])
        #expect(state.cachedSourceCount == 1)
    }

    @Test("stale progress cannot replace a newer query, including the same text repeated")
    func staleRequestIsIgnored() {
        var state = MailSearchProgressState()
        let old = state.begin(sources: [source])
        let current = state.begin(sources: [source])
        let applied5 = state.apply(
            MailSearchUpdate(headers: [header("stale", 2)], coverage: .server),
            source: source,
            request: old
        )
        #expect(!applied5)
        let applied6 = state.apply(
            MailSearchUpdate(headers: [header("new", 1)], coverage: .server, isComplete: true),
            source: source,
            request: current
        )
        #expect(applied6)
        #expect(state.headers(for: source).map(\.id) == ["new"])
        #expect(!state.isSearching)
        let late = state.apply(
            MailSearchUpdate(headers: [header("late", 3)], coverage: .server),
            source: source,
            request: current
        )
        #expect(!late)
    }

    @MainActor
    @Test("partial search pages preserve the open reader until final reconciliation")
    func partialPagesPreserveReader() {
        let selected = header("open", 3)
        let navigation = MailNavigationState(currentFolderHeaders: [selected, header("reply", 1, threadID: "open")])
        navigation.selectedMessageID = selected.id
        navigation.installPartialSearchHeaders([header("match", 2)])
        #expect(navigation.selectedMessageID == "open")
        #expect(navigation.currentFolderHeaders.map(\.id) == ["match", "open", "reply"])
    }

    @Test("failed sources keep partial results and cannot claim complete server coverage")
    func failureRetainsPartialResults() {
        var state = MailSearchProgressState()
        let request = state.begin(sources: [source])
        _ = state.apply(MailSearchUpdate(headers: [header("partial", 1)], coverage: .server), source: source, request: request)
        state.fail(source: source, request: request)
        #expect(state.hasFailure)
        #expect(!state.isSearching)
        #expect(state.headers(for: source).count == 1)
    }

    private func header(_ id: String, _ date: TimeInterval, threadID: String? = nil) -> MessageHeader {
        MessageHeader(
            id: id,
            threadID: threadID ?? id,
            folderID: "INBOX",
            from: Correspondent(email: "sender@example.org"),
            to: [],
            subject: id,
            snippet: "",
            date: Date(timeIntervalSince1970: date)
        )
    }
}

private actor SearchWorkerSignal {
    private var ready = false
    private var waiter: CheckedContinuation<Void, Never>?
    func signal() { ready = true; waiter?.resume(); waiter = nil }
    func wait() async {
        guard !ready else { return }
        await withCheckedContinuation { waiter = $0 }
    }
}
