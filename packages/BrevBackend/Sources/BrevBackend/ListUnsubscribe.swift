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
