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

public struct ListUnsubscribeOptions: Sendable, Hashable, Codable {
    public let methods: [ListUnsubscribeMethod]

    public init(methods: [ListUnsubscribeMethod]) {
        self.methods = methods
    }

    public var requiresExplicitConfirmation: Bool {
        !methods.isEmpty
    }

    public static func parse(
        listUnsubscribe: String?,
        listUnsubscribePost: String?
    ) -> ListUnsubscribeOptions {
        let supportsOneClick = listUnsubscribePost?
            .localizedCaseInsensitiveContains("List-Unsubscribe=One-Click") == true
        let methods = unsubscribeURLs(from: listUnsubscribe).compactMap { url -> ListUnsubscribeMethod? in
            switch url.scheme?.lowercased() {
            case "https":
                guard isSafeHTTPSURL(url) else { return nil }
                return .https(url, supportsOneClick: supportsOneClick)
            case "mailto":
                guard isSafeMailtoURL(url) else { return nil }
                return .mailto(url)
            default:
                return nil
            }
        }
        return ListUnsubscribeOptions(methods: methods)
    }

    private static func unsubscribeURLs(from header: String?) -> [URL] {
        guard let header else { return [] }
        return header
            .split(separator: ",")
            .compactMap { component -> URL? in
                var value = component.trimmingCharacters(in: .whitespacesAndNewlines)
                if value.hasPrefix("<"), value.hasSuffix(">") {
                    value.removeFirst()
                    value.removeLast()
                }
                return URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines))
            }
    }

    private static func isSafeHTTPSURL(_ url: URL) -> Bool {
        guard url.host?.isEmpty == false else { return false }
        return url.user == nil && url.password == nil
    }

    private static func isSafeMailtoURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "mailto" else { return false }
        let absoluteString = url.absoluteString
        guard let schemeSeparator = absoluteString.firstIndex(of: ":") else { return false }
        let payload = absoluteString[absoluteString.index(after: schemeSeparator)...]
        let addressEnd = payload.firstIndex { character in
            character == "?" || character == "#"
        } ?? payload.endIndex
        guard let decodedAddress = String(payload[..<addressEnd]).removingPercentEncoding else {
            return false
        }
        let address = decodedAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return address.contains("@") && !address.contains(where: \.isWhitespace)
    }
}

public enum ListUnsubscribeMethod: Sendable, Hashable, Codable {
    case https(URL, supportsOneClick: Bool)
    case mailto(URL)
}

/// Optional read-only seam exposing cached `List-Unsubscribe` options without
/// performing any network fetch (ADR-0006, ADR-0028, #295).
public protocol CachedListUnsubscribeProviding: Sendable {
    /// Returns parsed `List-Unsubscribe` options from locally cached metadata
    /// for `messageID`, or `nil` when uncached or absent.
    func cachedListUnsubscribe(
        for messageID: MessageHeader.ID,
        sourceID: MailSourceID
    ) async -> ListUnsubscribeOptions?

    /// Returns whether locally cached headers mark `messageID` as bulk or
    /// auto-generated mail (`Precedence: bulk|list|junk` or `Auto-Submitted`).
    func cachedIsBulkPrecedence(
        for messageID: MessageHeader.ID,
        sourceID: MailSourceID
    ) async -> Bool
}

public extension CachedListUnsubscribeProviding {
    func cachedIsBulkPrecedence(
        for _: MessageHeader.ID,
        sourceID _: MailSourceID
    ) async -> Bool {
        false
    }
}

public extension ListUnsubscribeOptions {
    /// Evaluates standard bulk-mail precedence headers (`Precedence` / `Auto-Submitted`).
    static func isBulkPrecedence(precedence: String?, autoSubmitted: String?) -> Bool {
        if let precedence {
            let normalized = precedence.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized == "bulk" || normalized == "list" || normalized == "junk" {
                return true
            }
        }
        if let autoSubmitted {
            let normalized = autoSubmitted.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !normalized.isEmpty, normalized != "no" {
                return true
            }
        }
        return false
    }
}
