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

import Foundation

/// Groups messages into conversations from their RFC 5322 reply links.
///
/// IMAP has no thread identity of its own: a plain server hands back
/// `Message-ID` and `In-Reply-To` and nothing else. This resolver joins
/// messages that reference each other into one conversation and names it
/// with a stable id, so `MessageHeader.threadID` means the same thing for a
/// standards IMAP account as it does for a provider that threads server-side
/// (ADR-0052).
///
/// The link graph is walked with union-find. A referenced parent that is not
/// itself in `headers` still becomes a node, so two replies to a message that
/// was never fetched — a mail sent from another client, a root filed in
/// another folder — land in the same conversation instead of splitting.
public enum MessageThreadResolver {
    /// Returns `headers` with `threadID` rewritten to the conversation each
    /// message belongs to. Order is preserved; nothing else is modified.
    ///
    /// Messages with no reply links keep a conversation of their own, which is
    /// the same `threadID` they had before resolution.
    public static func resolved(_ headers: [MessageHeader]) -> [MessageHeader] {
        let threadIDs = threadIDsByHeaderID(for: headers)
        return headers.map { header in
            guard let threadID = threadIDs[header.id],
                  threadID != header.threadID
            else {
                return header
            }
            return header.withThreadID(threadID)
        }
    }

    /// The conversation id for each header, keyed by `MessageHeader.id`.
    ///
    /// Exposed separately so callers that only need the grouping — counts,
    /// diagnostics, tests — do not have to rebuild the header array.
    public static func threadIDsByHeaderID(for headers: [MessageHeader]) -> [MessageHeader.ID: String] {
        guard headers.count > 1 else {
            return headers.reduce(into: [:]) { result, header in
                result[header.id] = header.threadID
            }
        }

        var union = DisjointSet()
        var nodesByHeaderID: [MessageHeader.ID: String] = [:]

        for header in headers {
            let node = node(for: header)
            nodesByHeaderID[header.id] = node
            union.insert(node)
            guard let parent = normalized(header.inReplyTo) else { continue }
            union.insert(parent)
            union.unite(node, parent)
        }

        // Name each conversation after its oldest message. Referenced-but-absent
        // parents are deliberately not eligible: their date is unknown, and a
        // node that never appears in the list would be an opaque thread id.
        var namesByRoot: [String: (threadID: String, date: Date, node: String)] = [:]
        for header in headers {
            guard let node = nodesByHeaderID[header.id] else { continue }
            let root = union.find(node)
            let candidate = (threadID: header.threadID, date: header.date, node: node)
            guard let current = namesByRoot[root] else {
                namesByRoot[root] = candidate
                continue
            }
            if candidate.date < current.date
                || (candidate.date == current.date && candidate.node < current.node) {
                namesByRoot[root] = candidate
            }
        }

        return headers.reduce(into: [:]) { result, header in
            guard let node = nodesByHeaderID[header.id],
                  let name = namesByRoot[union.find(node)]
            else {
                result[header.id] = header.threadID
                return
            }
            result[header.id] = name.threadID
        }
    }

    /// Graph node for a message: its Message-ID when it has one, otherwise a
    /// private key that can never collide with a real Message-ID.
    private static func node(for header: MessageHeader) -> String {
        guard let messageID = normalized(header.messageID) else {
            return "brev-header-id:\(header.id)"
        }
        return messageID
    }

    private static func normalized(_ messageID: String?) -> String? {
        guard let trimmed = messageID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}

/// Incremental variant of `MessageThreadResolver`: keeps the union-find
/// forest and conversation names alive between calls so a new page or a
/// flag-only update does not re-resolve the whole cached folder.
///
/// `update(with:)` diffs incoming headers by the exact fields the batch
/// resolver reads (`messageID`, `inReplyTo`, `threadID`, `date`) — flag
/// churn is `.unchanged`. Pure additions extend the forest in place; a
/// removal or a changed key triggers a full rebuild, since union-find has
/// no delete.
public struct IncrementalThreadResolver: Sendable {
    /// The fields thread resolution depends on. Compared rather than hashed:
    /// Swift `String ==` short-circuits on identical storage, which is the
    /// common case when a cached snapshot is re-presented.
    private struct ThreadKey: Hashable, Sendable {
        var messageID: String?
        var inReplyTo: String?
        var threadID: String
        var date: Date
    }

    /// How the last `update(with:)` changed the resolved state.
    public enum Update: Equatable, Sendable {
        /// Every incoming id was already known with an identical key.
        case unchanged
        /// Only new ids arrived; the forest was extended in place.
        case incremental(added: Int)
        /// A removal, key change, or empty input forced a full rebuild.
        case rebuilt(reason: String)
    }

    private var keys: [MessageHeader.ID: ThreadKey] = [:]
    private var union = DisjointSet()
    private var nodesByHeaderID: [MessageHeader.ID: String] = [:]
    private var namesByRoot: [String: (threadID: String, date: Date, node: String)] = [:]

    public init() {}

    /// Feeds the current known header set. Idempotent for identical input.
    public mutating func update(with headers: [MessageHeader]) -> Update {
        if headers.isEmpty {
            guard !keys.isEmpty else { return .unchanged }
            rebuild(headers)
            return .rebuilt(reason: "empty")
        }

        var added: [MessageHeader] = []
        var changed = false
        var incomingIDs: Set<MessageHeader.ID> = []
        incomingIDs.reserveCapacity(headers.count)
        for header in headers {
            incomingIDs.insert(header.id)
            let key = ThreadKey(
                messageID: header.messageID,
                inReplyTo: header.inReplyTo,
                threadID: header.threadID,
                date: header.date
            )
            if let existing = keys[header.id] {
                if existing != key { changed = true }
            } else {
                added.append(header)
            }
        }
        let removed = keys.keys.count { !incomingIDs.contains($0) }

        if changed || removed > 0 {
            rebuild(headers)
            return .rebuilt(reason: removed > 0 ? "removed" : "changed")
        }
        guard !added.isEmpty else { return .unchanged }

        for header in added {
            let node = Self.node(for: header)
            keys[header.id] = ThreadKey(
                messageID: header.messageID,
                inReplyTo: header.inReplyTo,
                threadID: header.threadID,
                date: header.date
            )
            nodesByHeaderID[header.id] = node
            union.insert(node)
            if let parent = Self.normalized(header.inReplyTo) {
                union.insert(parent)
                uniteKeepingNames(node, parent)
            }
            let root = union.find(node)
            let candidate = (threadID: header.threadID, date: header.date, node: node)
            if let current = namesByRoot[root] {
                if Self.isBetter(candidate, than: current) {
                    namesByRoot[root] = candidate
                }
            } else {
                namesByRoot[root] = candidate
            }
        }
        return .incremental(added: added.count)
    }

    /// The resolved conversation id for one known header, or nil when the
    /// id was never seen.
    public mutating func threadID(for id: MessageHeader.ID) -> String? {
        guard let node = nodesByHeaderID[id] else { return nil }
        return namesByRoot[union.find(node)]?.threadID ?? keys[id]?.threadID
    }

    /// The resolved conversation id for every known header. Mutating
    /// because `find` applies path halving.
    public mutating func threadIDs() -> [MessageHeader.ID: String] {
        var result: [MessageHeader.ID: String] = [:]
        result.reserveCapacity(nodesByHeaderID.count)
        for (id, node) in nodesByHeaderID {
            guard let threadID = namesByRoot[union.find(node)]?.threadID ?? keys[id]?.threadID
            else { continue }
            result[id] = threadID
        }
        return result
    }

    /// Unites two nodes' roots; when both roots already carry a name, the
    /// merged root keeps the older one (same rule the batch naming pass
    /// applies: smaller date, then smaller node).
    private mutating func uniteKeepingNames(_ lhs: String, _ rhs: String) {
        let lhsRoot = union.find(lhs)
        let rhsRoot = union.find(rhs)
        guard lhsRoot != rhsRoot else { return }
        let lhsName = namesByRoot[lhsRoot]
        let rhsName = namesByRoot[rhsRoot]
        union.unite(lhsRoot, rhsRoot)
        let mergedRoot = union.find(lhsRoot)
        namesByRoot.removeValue(forKey: lhsRoot)
        namesByRoot.removeValue(forKey: rhsRoot)
        switch (lhsName, rhsName) {
        case (let lhs?, let rhs?):
            namesByRoot[mergedRoot] = Self.isBetter(lhs, than: rhs) ? lhs : rhs
        case (let lhs?, nil):
            namesByRoot[mergedRoot] = lhs
        case (nil, let rhs?):
            namesByRoot[mergedRoot] = rhs
        case (nil, nil):
            break
        }
    }

    /// Re-runs the batch algorithm's exact steps over `headers`.
    private mutating func rebuild(_ headers: [MessageHeader]) {
        keys.removeAll(keepingCapacity: true)
        union = DisjointSet()
        nodesByHeaderID.removeAll(keepingCapacity: true)
        namesByRoot.removeAll(keepingCapacity: true)

        for header in headers {
            keys[header.id] = ThreadKey(
                messageID: header.messageID,
                inReplyTo: header.inReplyTo,
                threadID: header.threadID,
                date: header.date
            )
            let node = Self.node(for: header)
            nodesByHeaderID[header.id] = node
            union.insert(node)
            guard let parent = Self.normalized(header.inReplyTo) else { continue }
            union.insert(parent)
            union.unite(node, parent)
        }

        for header in headers {
            guard let node = nodesByHeaderID[header.id] else { continue }
            let root = union.find(node)
            let candidate = (threadID: header.threadID, date: header.date, node: node)
            guard let current = namesByRoot[root] else {
                namesByRoot[root] = candidate
                continue
            }
            if Self.isBetter(candidate, than: current) {
                namesByRoot[root] = candidate
            }
        }
    }

    private static func isBetter(
        _ candidate: (threadID: String, date: Date, node: String),
        than current: (threadID: String, date: Date, node: String)
    ) -> Bool {
        candidate.date < current.date
            || (candidate.date == current.date && candidate.node < current.node)
    }

    private static func node(for header: MessageHeader) -> String {
        guard let messageID = normalized(header.messageID) else {
            return "brev-header-id:\(header.id)"
        }
        return messageID
    }

    private static func normalized(_ messageID: String?) -> String? {
        guard let trimmed = messageID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}

/// Minimal union-find over string nodes, with path halving and union by size.
private struct DisjointSet: Sendable {
    private var parents: [String: String] = [:]
    private var sizes: [String: Int] = [:]

    mutating func insert(_ node: String) {
        guard parents[node] == nil else { return }
        parents[node] = node
        sizes[node] = 1
    }

    mutating func find(_ node: String) -> String {
        var current = node
        while let parent = parents[current], parent != current {
            parents[current] = parents[parent] ?? parent
            current = parents[current] ?? parent
        }
        return current
    }

    mutating func unite(_ lhs: String, _ rhs: String) {
        let lhsRoot = find(lhs)
        let rhsRoot = find(rhs)
        guard lhsRoot != rhsRoot else { return }
        let lhsSize = sizes[lhsRoot] ?? 1
        let rhsSize = sizes[rhsRoot] ?? 1
        if lhsSize < rhsSize {
            parents[lhsRoot] = rhsRoot
            sizes[rhsRoot] = lhsSize + rhsSize
        } else {
            parents[rhsRoot] = lhsRoot
            sizes[lhsRoot] = lhsSize + rhsSize
        }
    }
}
