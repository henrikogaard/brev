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
import Foundation

/// Keeps query ownership, source identity and partial coverage together.
struct MailSearchProgressState {
    private struct Source {
        var headers: [MessageHeader] = []
        var seen = Set<MessageHeader.ID>()
        var coverage: MailSearchCoverage?
        var complete = false
        var failed = false

        mutating func apply(_ update: MailSearchUpdate) {
            if update.replacesResults || coverage != update.coverage {
                headers = []
                seen = []
            }
            coverage = update.coverage
            complete = update.isComplete
            let added = update.headers.filter { seen.insert($0.id).inserted }.sorted(by: Self.precedes)
            guard !added.isEmpty else { return }
            // Merge already-sorted results instead of sorting the entire mailbox per page.
            var merged: [MessageHeader] = []
            merged.reserveCapacity(headers.count + added.count)
            var old = 0, new = 0
            while old < headers.count, new < added.count {
                if Self.precedes(headers[old], added[new]) {
                    merged.append(headers[old])
                    old += 1
                } else {
                    merged.append(added[new])
                    new += 1
                }
            }
            merged.append(contentsOf: headers.dropFirst(old))
            merged.append(contentsOf: added.dropFirst(new))
            headers = merged
        }

        static func precedes(_ lhs: MessageHeader, _ rhs: MessageHeader) -> Bool {
            lhs.date == rhs.date ? lhs.id > rhs.id : lhs.date > rhs.date
        }
    }

    private(set) var request: UUID?
    private var sources: [MailSourceID: Source] = [:]
    var sourceCount: Int { sources.count }
    var isSearching: Bool { sources.values.contains { !$0.complete } }
    var hasFailure: Bool { sources.values.contains(where: \.failed) }
    var canRetry: Bool { hasFailure && !isSearching }
    var cachedSourceCount: Int { sources.values.filter { $0.coverage == .cached }.count }
    var unverifiedSourceCount: Int { sources.values.filter { $0.coverage == .unverified }.count }

    mutating func begin(sources ids: [MailSourceID]) -> UUID {
        let id = UUID()
        request = id
        sources = Dictionary(ids.map { ($0, Source()) }, uniquingKeysWith: { first, _ in first })
        return id
    }

    @discardableResult
    mutating func apply(_ update: MailSearchUpdate, source: MailSourceID, request id: UUID) -> Bool {
        guard request == id, var state = sources[source], !state.failed, !state.complete else { return false }
        state.apply(update)
        sources[source] = state
        return true
    }

    mutating func fail(source: MailSourceID, request id: UUID) {
        guard request == id, var state = sources[source] else { return }
        state.complete = true
        state.failed = true
        sources[source] = state
    }

    /// Ends abandoned work without allowing an old task to settle a newer query.
    mutating func finish(request id: UUID) {
        guard request == id else { return }
        for source in sources.keys {
            guard var state = sources[source], !state.complete else { continue }
            state.complete = true
            state.failed = true
            sources[source] = state
        }
    }

    func headers(for source: MailSourceID) -> [MessageHeader] { sources[source]?.headers ?? [] }
}

/// Adapts optional provider progress without claiming coverage for older array-only adapters.
enum MailSearchExecution {
    static func run(
        backend: any MailBackend,
        query: SearchQuery,
        sourceID: MailSourceID?,
        onUpdate: @escaping MailSearchProgressHandler
    ) async throws -> [MessageHeader] {
        if let progressive = backend.extensionService(ProgressiveMailSearching.self) {
            return try await progressive.searchWithProgress(query, sourceID: sourceID, onUpdate: onUpdate)
        }
        let results: [MessageHeader]
        if let sourceID {
            results = try await backend.search(query, sourceID: sourceID)
        } else {
            results = try await backend.search(query)
        }
        try Task.checkCancellation()
        await onUpdate(MailSearchUpdate(
            headers: results,
            coverage: query.execution == .cacheOnly ? .cached : .unverified,
            replacesResults: true,
            isComplete: true
        ))
        try Task.checkCancellation()
        return results
    }
}

extension MailNavigationState {
    /// Keeps the open reader stable until the search has definitive final coverage.
    func installPartialSearchHeaders(_ headers: [MessageHeader]) {
        let selected = selectedMessageID.flatMap { id in currentFolderHeaders.first { $0.id == id } }
        let retained = selected.map { selected in currentFolderHeaders.filter { $0.threadID == selected.threadID } } ?? []
        currentFolderHeaders = headers
        let included = Set(headers.map(\.id))
        currentFolderHeaders.append(contentsOf: retained.filter { !included.contains($0.id) })
    }
}
