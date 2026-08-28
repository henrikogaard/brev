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

/// A parsed `mailto:` URL per RFC 6068.
///
/// The path holds the primary comma-separated recipients; the query carries
/// header fields (`to`, `cc`, `bcc`, `subject`, `body`). All components are
/// percent-decoded. Unlike HTML form encoding, `+` is a literal character in
/// `mailto:` URLs and is never turned into a space.
public struct MailtoURL: Equatable, Sendable {
    public var to: [String]
    public var cc: [String]
    public var bcc: [String]
    public var subject: String?
    public var body: String?

    /// `true` when the URL carries no recipients and no header values.
    public var isEmpty: Bool {
        to.isEmpty && cc.isEmpty && bcc.isEmpty && subject == nil && body == nil
    }

    /// Parses `url`; returns `nil` when its scheme is not `mailto`.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == "mailto" else { return nil }
        // Work on the raw string rather than URLComponents: `mailto:` URLs
        // have no authority, and RFC 6068 wants a plain percent-decode of
        // each field with `+` preserved.
        var raw = url.absoluteString.dropFirst("mailto:".count)
        if let fragment = raw.firstIndex(of: "#") {
            raw = raw[..<fragment]
        }
        let pathPart: Substring
        let queryPart: Substring?
        if let question = raw.firstIndex(of: "?") {
            pathPart = raw[..<question]
            queryPart = raw[raw.index(after: question)...]
        } else {
            pathPart = raw
            queryPart = nil
        }

        var to = Self.addresses(fromEncoded: pathPart)
        var cc: [String] = []
        var bcc: [String] = []
        var subject: String?
        var body: String?
        for pair in queryPart?.split(separator: "&", omittingEmptySubsequences: true) ?? [] {
            let name: Substring
            let value: Substring
            if let equals = pair.firstIndex(of: "=") {
                name = pair[..<equals]
                value = pair[pair.index(after: equals)...]
            } else {
                name = pair
                value = ""
            }
            switch Self.decode(name).lowercased() {
            case "to": to += Self.addresses(fromEncoded: value)
            case "cc": cc += Self.addresses(fromEncoded: value)
            case "bcc": bcc += Self.addresses(fromEncoded: value)
            case "subject": subject = Self.decode(value)
            case "body": body = Self.decode(value)
            default: break
            }
        }
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.body = body
    }

    private static func decode(_ encoded: Substring) -> String {
        String(encoded).removingPercentEncoding ?? String(encoded)
    }

    private static func addresses(fromEncoded encoded: Substring) -> [String] {
        decode(encoded)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
