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
import SwiftUI
import Testing

@Suite("Message list appear load", .serialized)
@MainActor
struct MessageListAppearLoadTests {
    @Test("an appearance with empty search text fetches the first page once", .timeLimit(.minutes(1)))
    func appearFetchesFirstPageOnce() async throws {
        let list = HostedList()
        defer { list.close() }
        try await list.waitForHeaders(["a", "b", "c"])
        try await list.settle()
        #expect(list.backend.firstPageFetchCount == 1)
    }

    @Test("clearing the search text reloads the folder once", .timeLimit(.minutes(1)))
    func clearingSearchReloadsFolderOnce() async throws {
        let list = HostedList()
        defer { list.close() }
        try await list.waitForHeaders(["a", "b", "c"])
        list.navigation.searchText = "b"
        try await list.waitForHeaders(["b"])
        #expect(list.backend.searchCount == 1)
        list.navigation.searchText = ""
        try await list.waitForHeaders(["a", "b", "c"])
        try await list.settle()
        #expect(list.backend.firstPageFetchCount == 2)
    }

    @Test("a search option change with empty search text does not refetch the folder", .timeLimit(.minutes(1)))
    func searchOptionChangeWithoutTextKeepsFolderPage() async throws {
        let list = HostedList()
        defer { list.close() }
        try await list.waitForHeaders(["a", "b", "c"])
        try await list.settle()
        // What `reconcileSearchExecutionWithBackendCapabilities()` does on a folder
        // switch to a backend without the selected search mode.
        list.navigation.searchExecution = .serverOnly
        try await list.settle()
        #expect(list.backend.firstPageFetchCount == 1)
    }

    @Test("a search option change with search text runs the search again", .timeLimit(.minutes(1)))
    func searchOptionChangeWithTextSearchesAgain() async throws {
        let list = HostedList(searchText: "b")
        defer { list.close() }
        try await list.waitForHeaders(["b"])
        try await list.settle()
        list.navigation.searchExecution = .serverOnly
        // The re-run goes through the search debounce, so wait for it rather
        // than for a fixed interval; a slow CI runner outlasts `settle()`.
        try await list.waitForSearchCount(2)
        #expect(list.backend.searchCount == 2)
        #expect(list.backend.firstPageFetchCount == 0)
    }

    @Test("an appearance with search text searches once and skips the folder page", .timeLimit(.minutes(1)))
    func appearWithSearchTextSearchesOnce() async throws {
        let list = HostedList(searchText: "b")
        defer { list.close() }
        try await list.waitForHeaders(["b"])
        try await list.settle()
        #expect(list.backend.searchCount == 1)
        #expect(list.backend.firstPageFetchCount == 0)
    }
}

/// A `MessageListView` in a window, so its `.task` and `.onChange` modifiers run.
@MainActor
private struct HostedList {
    let backend: FirstPageCountingBackend
    let navigation = MailNavigationState()
    private let window: NSWindow

    init(searchText: String = "") {
        let folder = Folder(id: "inbox", name: "Inbox", role: .inbox)
        let headers = ["a", "b", "c"].enumerated().map { index, id in
            MessageHeader(id: id, threadID: id, folderID: folder.id,
                          from: Correspondent(email: "fixture@example.org"),
                          subject: id, snippet: "", date: Date(timeIntervalSince1970: Double(300 - index)),
                          isRead: false)
        }
        backend = FirstPageCountingBackend(folder: folder, headers: headers)
        let source = MailSourceID(accountID: backend.account.id, mailboxID: backend.account.id)
        navigation.selectedFolderID = folder.id
        navigation.selectedSourceID = source
        navigation.searchText = searchText
        let host = NSHostingView(rootView: MessageListView(
            navigation: navigation, backend: backend, sourceID: source,
            folder: folder, allFolders: [folder],
            localMessageWorkflowState: .constant(.defaults),
            composeActions: MailComposePresentationActions(
                newMessage: {}, reply: { _ in }, replyAll: { _ in }, forward: { _ in }
            )
        ))
        host.frame = CGRect(x: 0, y: 0, width: 600, height: 600)
        window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
    }

    func close() { window.close() }

    func waitForHeaders(_ ids: [String]) async throws {
        while navigation.currentFolderHeaders.map(\.id) != ids {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Waits for the backend to have run `count` searches, for at most ten seconds.
    func waitForSearchCount(_ count: Int) async throws {
        for _ in 0 ..< 1000 where backend.searchCount < count {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Leaves room for a redundant load to start; nothing signals that one did not.
    func settle() async throws {
        try await Task.sleep(for: .milliseconds(300))
    }
}

/// Counts first-page fetches. It answers on the main actor without suspending, like a
/// backend serving the page from a warm cache, so a load has always finished before the
/// next main-actor job runs and a redundant one cannot hide behind the in-flight check.
private final class FirstPageCountingBackend: MailBackend, @unchecked Sendable {
    let account = BrevAccount(id: "counting", displayName: "Counting", emailAddress: "counting@example.org")
    let capabilities: BackendCapabilities = []
    private let folder: Folder
    private let headers: [MessageHeader]
    @MainActor private(set) var firstPageFetchCount = 0
    @MainActor private(set) var searchCount = 0

    init(folder: Folder, headers: [MessageHeader]) {
        self.folder = folder
        self.headers = headers
    }

    @MainActor
    func messages(in _: Folder, pageToken: String?) async throws
        -> (headers: [MessageHeader], nextPageToken: String?) {
        if pageToken == nil { firstPageFetchCount += 1 }
        return (headers, nil)
    }

    @MainActor
    func messages(in folder: Folder, sourceID _: MailSourceID, pageToken: String?) async throws
        -> (headers: [MessageHeader], nextPageToken: String?) {
        try await messages(in: folder, pageToken: pageToken)
    }

    @MainActor
    func search(_ query: SearchQuery) async throws -> [MessageHeader] {
        searchCount += 1
        return headers.filter { $0.subject == query.text }
    }

    @MainActor
    func search(_ query: SearchQuery, sourceID _: MailSourceID) async throws -> [MessageHeader] {
        try await search(query)
    }

    func connect() async throws {}
    func disconnect() async {}
    func folders() async throws -> [Folder] { [folder] }
    func refresh(folder _: Folder) async throws {}

    func currentMailbox() async throws -> Mailbox {
        Mailbox(id: account.id, email: account.emailAddress, displayName: account.displayName, isPrimary: true)
    }

    func switchMailbox(id _: String) async throws {}

    func body(for messageID: String) async throws -> MessageBody {
        MessageBody(messageID: messageID)
    }

    func setRead(_: Bool, for _: [String]) async throws {}
    func setFlagged(_: Bool, for _: [String]) async throws {}
    func move(messageIDs _: [String], to _: Folder) async throws {}
    func delete(messageIDs _: [String]) async throws {}
    func save(draft: Draft) async throws -> Draft { draft }
    func discard(draftID _: String) async throws {}
    func send(draft _: Draft) async throws -> SendResult { SendResult() }

    func calendarEvent(from _: String) async throws -> CalendarEvent {
        throw MailBackendError.notSupported(capabilities)
    }

    func replyToCalendarInvite(messageID _: String, response _: AttendeeState) async throws {}
    func subscribeToChanges() -> AsyncStream<MailEvent> { AsyncStream { $0.finish() } }

    func sourceID(for mailbox: Mailbox) -> MailSourceID {
        MailSourceID(accountID: account.id, mailboxID: mailbox.id)
    }

    func extensionService<Service>(_: Service.Type) -> Service? { nil }
}
#endif
