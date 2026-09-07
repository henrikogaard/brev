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

/// Resolves only proven reply links; it never merges subjects or changes the selected identity.
public enum ConversationMembershipResolver {
    private enum Node: Hashable { case message(ConversationLocation), identifier(String) }
    private struct Fingerprint: Hashable {
        let sender: String
        let recipients: [String]
        let date: Date
        let subject: String
        init(_ header: MessageHeader) {
            sender = header.from.email.lowercased()
            recipients = header.to.map { $0.email.lowercased() }.sorted()
            date = header.date
            subject = header.subject
        }
    }

    /// Resolves a cached component, retaining physical copies and reporting ambiguous identifiers.
    public static func cached(around anchor: ConversationMember,
                              candidates: [ConversationMember]) throws -> ConversationSnapshot {
        guard candidates.allSatisfy({ $0.sourceID == anchor.sourceID }) else { throw ConversationLookupError.foreignSource }
        var seen = Set<ConversationLocation>()
        let members = ([anchor] + candidates).filter { seen.insert($0.location).inserted }
        var links: [ConversationLocation: Set<String>] = [:]
        var owners: [String: Set<Fingerprint>] = [:]
        var ownerCounts: [String: Int] = [:]
        for member in members {
            let own = try identifiers(in: member.header.rfcMessageID)
            guard own.count <= 1 else { throw ConversationLookupError.invalidMetadata }
            if let id = own.first {
                ownerCounts[id, default: 0] += 1
                owners[id, default: []].insert(Fingerprint(member.header))
            }
            guard (member.references ?? []).reduce(0, { $0 + $1.utf8.count }) <= 65536
            else { throw ConversationLookupError.invalidMetadata }
            var references = try identifiers(in: member.header.inReplyTo)
            for value in member.references ?? [] {
                try references.append(contentsOf: identifiers(in: value))
            }
            links[member.location] = Set(own + references)
        }
        let unsafe = Set(owners.filter { $0.value.count > 1 }.map(\.key))
        let ambiguous = Set(ownerCounts.filter { $0.value > 1 }.map(\.key))
        var graph: [Node: Set<Node>] = [:]
        for member in members {
            let node = Node.message(member.location)
            for id in links[member.location, default: []] where !unsafe.contains(id) {
                graph[node, default: []].insert(.identifier(id))
                graph[.identifier(id), default: []].insert(node)
            }
        }
        var visited: Set<Node> = [.message(anchor.location)]
        var queue: [Node] = [.message(anchor.location)]
        var index = 0
        while index < queue.count {
            for next in graph[queue[index], default: []] where visited.insert(next).inserted {
                queue.append(next)
            }
            index += 1
        }
        let related = members.filter { visited.contains(.message($0.location)) }
        let relevantAmbiguities = related.reduce(into: Set<String>()) { result, member in
            result.formUnion(links[member.location, default: []].intersection(ambiguous))
        }
        return try ConversationSnapshot(anchor: anchor.location, members: related, coverage: .cached,
                                        ambiguousIdentifiers: relevantAmbiguities.sorted())
    }

    /// Parses bracketed RFC identifiers or one legacy opaque ID without guessing from prose.
    public static func identifiers(in value: String?) throws -> [String] {
        guard let value else { return [] }
        guard value.utf8.count <= 65536,
              !value.unicodeScalars.contains(where: {
                  ($0.value < 32 && ![9, 10, 13].contains($0.value)) || $0.value == 127
              }) else { throw ConversationLookupError.invalidMetadata }
        let trimmed = try removingComments(value).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var remaining = trimmed[...]
        var result: [String] = []
        while let start = remaining.firstIndex(of: "<") {
            guard remaining[..<start].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { throw ConversationLookupError.invalidMetadata }
            let content = remaining.index(after: start)
            guard let end = remaining[content...].firstIndex(of: ">") else { throw ConversationLookupError.invalidMetadata }
            let token = String(remaining[content ..< end])
            guard !token.isEmpty,
                  !token.contains(where: { $0.isWhitespace || $0 == "<" }) else { throw ConversationLookupError.invalidMetadata }
            result.append(token)
            remaining = remaining[remaining.index(after: end)...]
        }
        if result.isEmpty {
            guard !trimmed.contains(where: { $0.isWhitespace || "<>()".contains($0) })
            else { throw ConversationLookupError.invalidMetadata }
            result = [trimmed]
        } else if !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ConversationLookupError.invalidMetadata
        }
        return Array(Set(result)).sorted()
    }

    private static func removingComments(_ value: String) throws -> String {
        var result = ""
        var depth = 0
        var escaped = false
        var inIdentifier = false
        for character in value {
            if depth > 0 {
                if escaped { escaped = false; continue }
                if character == "\\" {
                    escaped = true
                } else if character == "(" {
                    depth += 1
                } else if character == ")" {
                    depth -= 1
                }
                continue
            }
            if character == "(" {
                guard !inIdentifier else { throw ConversationLookupError.invalidMetadata }
                depth = 1
                result.append(" ")
                continue
            }
            if character == ")" { throw ConversationLookupError.invalidMetadata }
            if character == "<" { inIdentifier = true }
            if character == ">" { inIdentifier = false }
            result.append(character)
        }
        guard depth == 0 else { throw ConversationLookupError.invalidMetadata }
        return result
    }
}
