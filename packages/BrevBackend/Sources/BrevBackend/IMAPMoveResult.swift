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

/// Destination UID mapping returned by an IMAP UIDPLUS move or copy.
public struct IMAPMoveResult: Sendable, Equatable {
    public let uidValidity: Int?
    public let uidMappings: [Int: Int]

    /// Creates a confirmed mapping; an empty mapping means safe Undo is unavailable.
    public init(uidValidity: Int? = nil, uidMappings: [Int: Int] = [:]) {
        self.uidValidity = uidValidity
        self.uidMappings = uidMappings
    }

    static func parse(responses: [String], requestedUIDs: [Int]) -> IMAPMoveResult {
        let requested = Set(requestedUIDs)
        for response in responses {
            guard response.split(separator: " ", maxSplits: 2).dropFirst().first?.uppercased() == "OK" else { continue }
            guard let marker = response.range(of: "[COPYUID ", options: .caseInsensitive),
                  let end = response[marker.upperBound...].firstIndex(of: "]") else { continue }
            let tokens = response[marker.upperBound ..< end].split(whereSeparator: \.isWhitespace)
            guard tokens.count == 3, let validity = validUID(tokens[0]),
                  let sources = uidSequence(tokens[1], maximumCount: requested.count),
                  let destinations = uidSequence(tokens[2], maximumCount: requested.count),
                  sources.count == destinations.count,
                  Set(sources).isSubset(of: requested) else { return IMAPMoveResult() }
            return IMAPMoveResult(
                uidValidity: validity,
                uidMappings: Dictionary(uniqueKeysWithValues: zip(sources, destinations))
            )
        }
        return IMAPMoveResult()
    }

    private static func validUID(_ text: Substring) -> Int? {
        guard let first = text.utf8.first, (49 ... 57).contains(first),
              text.utf8.allSatisfy({ (48 ... 57).contains($0) }), let value = Int(text),
              (1 ... Int(UInt32.max)).contains(value) else { return nil }
        return value
    }

    private static func uidSequence(_ text: Substring, maximumCount: Int) -> [Int]? {
        var values: [Int] = []
        for component in text.split(separator: ",", omittingEmptySubsequences: false) {
            let bounds = component.split(separator: ":", omittingEmptySubsequences: false)
            guard (1 ... 2).contains(bounds.count), let first = validUID(bounds[0]),
                  let last = validUID(bounds[bounds.count - 1]) else { return nil }
            // RFC 4315 ranges are ascending even when written 12:10. Never
            // expand more UIDs than the caller actually asked to move.
            let lower = min(first, last)
            let upper = max(first, last)
            guard upper - lower + 1 <= maximumCount - values.count else { return nil }
            values.append(contentsOf: lower ... upper)
        }
        guard !values.isEmpty, Set(values).count == values.count else { return nil }
        return values
    }
}
