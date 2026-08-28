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

/// Minimal union-find over string nodes, with path halving and union by size.
private struct DisjointSet {
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
