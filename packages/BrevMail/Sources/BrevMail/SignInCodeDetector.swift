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

/// Ephemeral extraction only, never sender eligibility or permission to display/open.
enum SignInCandidate: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    case code(String)
    case link(destination: String, host: String)

    var description: String { "SignInCandidate(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: EmptyCollection<Mirror.Child>()) }
}

/// A stateless, conservative plain-text recognizer; no callers are connected to mail.
/// HTML/Markdown must not be flattened into this input: doing so loses visible-link
/// evidence. Consent, provider trust and fresh-delivery checks belong outside it.
enum SignInCodeDetector {
    /// Returns at most one untrusted candidate, without fetching, caching or logging.
    static func detect(in text: String) -> SignInCandidate? {
        guard text.utf8.count <= 65536,
              !text.unicodeScalars.contains(where: { scalar in
                  CharacterSet.controlCharacters.contains(scalar)
                      && scalar != "\n" && scalar != "\r" && scalar != "\t"
              }),
              !contains(forbiddenBracketRegex, in: text),
              !contains(excludedContextRegex, in: text)
        else { return nil }

        let tokens = matches(tokenRegex, in: text).filter { range in
            text[range].contains(where: \.isNumber)
        }
        guard tokens.count <= 128 else { return nil }
        let contextual = tokens.filter { hasCodeContext(at: $0, in: text) }
        let links = matches(linkRegex, in: text)

        if !contextual.isEmpty {
            guard links.isEmpty, contextual.count == 1,
                  tokens.filter({ text[$0].count >= 4 }).count == 1,
                  let range = contextual.first,
                  validCode(at: range, in: text)
            else { return nil }
            return .code(String(text[range]))
        }

        guard links.count == 1, let range = links.first else { return nil }
        return linkCandidate(at: range, in: text)
    }

    private static let forbiddenBracketRegex = compile(#"[<>\[\]{}]"#)
    private static let excludedContextRegex = compile(
        #"\b(?:order|order\s+number|ordre\w*|bestilling\w*|invoice|faktura\w*|price|pris|amount|beløp|phone|telefon\w*|date|dato|unsubscribe|avmeld\w*|meld\s+av)\b"#
    )
    private static let tokenRegex = compile(#"[\p{L}\p{N}_]+"#)
    private static let linkRegex = compile(#"\b[a-z][a-z0-9+.-]*://[^\s]+"#)
    private static let codePrefixRegex = compile(
        #"\b(?:verification\s+code|sign[ -]in\s+code|login\s+code|one[ -]time\s+(?:code|password)|security\s+code|engangskode|bekreftelseskode|verifiseringskode|innloggingskode|kode\s+for\s+innlogging)\s*(?:(?:is|er)\s*)?[:=]?\s*$"#
    )
    private static let codeSuffixRegex = compile(#"^\s+(?:to\s+(?:sign\s+in|log\s+in)|for\s+å\s+logge\s+inn)\b"#)
    private static let linkContextRegex = compile(
        #"\b(?:sign[ -]in|log\s+in|logg\s+inn|verify\s+(?:your\s+)?(?:account|email)|bekreft\s+(?:din\s+)?(?:innlogging|e-post)|magic[ -]link)\b"#
    )
    private static let codeShapeRegex = compile(#"\A[A-Za-z0-9]{4,8}\z"#)
    private static let isoDateRegex = compile(#"\A(?:19|20)[0-9]{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12][0-9]|3[01])\z"#)
    private static let currencySuffixRegex = compile(#"^\s*(?:USD|EUR|NOK|kr\b|[$€£])"#)
    private static let trackingLinkRegex = compile(
        #"(?:/|\b)(?:track\w*|click|redirect\w*|unsubscribe|optout)(?:/|\b)|[?&](?:utm_\w*|url|redirect\w*|target)="#
    )
    private static let nestedSchemeRegex = compile(#"https?://|//"#)
    private static let visibleDomainRegex = compile(#"[\p{L}\p{N}][\p{L}\p{N}.-]*\.[\p{L}][\p{L}\p{N}-]*"#)
    private static let invalidDestinationRegex = compile(#"[\\<>\"'()\[\]{}]|[.,;!?]$|%(?![0-9a-f]{2})"#)
    private static let validHostRegex = compile(#"\A(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}\z"#)

    private static func compile(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static func hasCodeContext(at range: Range<String.Index>, in text: String) -> Bool {
        let before = String(text[..<range.lowerBound].suffix(96))
        let after = String(text[range.upperBound...].prefix(64))
        return contains(codePrefixRegex, in: before) || contains(codeSuffixRegex, in: after)
    }

    private static func validCode(at range: Range<String.Index>, in text: String) -> Bool {
        let value = String(text[range])
        guard value.unicodeScalars.allSatisfy(\.isASCII),
              contains(codeShapeRegex, in: value),
              !contains(isoDateRegex, in: value)
        else { return false }
        let before = text[..<range.lowerBound].last
        let after = text[range.upperBound...].first
        let separators = ".,/-+:$€£@%="
        if let before, separators.contains(before) { return false }
        if let after, ",/-+:@%=".contains(after) { return false }
        // A sentence-ending dot is fine, but not a decimal/date/domain continuation.
        if after == ".", let next = text[range.upperBound...].dropFirst().first,
           next.isLetter || next.isNumber || next == "-" || next == "_" { return false }
        let suffix = String(text[range.upperBound...].prefix(16))
        return !contains(currencySuffixRegex, in: suffix)
    }

    private static func linkCandidate(at range: Range<String.Index>, in text: String) -> SignInCandidate? {
        let destination = String(text[range])
        guard let host = destinationHost(destination),
              let decoded = destination.removingPercentEncoding,
              !decoded.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !decoded.contains("\\"),
              !contains(trackingLinkRegex, in: decoded),
              !contains(nestedSchemeRegex, in: String(decoded.dropFirst("https://".count)))
        else { return nil }

        let before = String(text[..<range.lowerBound].suffix(120))
        let after = String(text[range.upperBound...].prefix(120))
        guard contains(linkContextRegex, in: before) || contains(linkContextRegex, in: after) else { return nil }

        // Compare all visible domains outside the destination, with exact host
        // equality (not suffix matching). No cached message-analysis entry point.
        let visible = String(text[..<range.lowerBound]) + " " + String(text[range.upperBound...])
        guard !visible.unicodeScalars.contains(where: { !$0.isASCII && !CharacterSet.letters.contains($0) }),
              matches(visibleDomainRegex, in: visible)
              .allSatisfy({ String(visible[$0]).lowercased() == host })
        else { return nil }
        return .link(destination: destination, host: host)
    }

    private static func destinationHost(_ destination: String) -> String? {
        guard destination.unicodeScalars.allSatisfy(\.isASCII),
              !contains(invalidDestinationRegex, in: destination),
              let components = URLComponents(string: destination),
              components.scheme?.lowercased() == "https",
              components.user == nil, components.password == nil, components.port == nil,
              let host = components.host?.lowercased(),
              contains(validHostRegex, in: host),
              !host.split(separator: ".").contains(where: { $0.hasPrefix("xn--") }),
              let url = URL(string: destination, encodingInvalidCharacters: false),
              url.absoluteString == destination,
              let authority = destination.split(separator: "/", omittingEmptySubsequences: false).dropFirst(2).first,
              authority.split(whereSeparator: { $0 == "?" || $0 == "#" }).first?.lowercased() == host
        else { return nil }
        return host
    }

    private static func contains(_ regex: NSRegularExpression, in text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex ..< text.endIndex, in: text)) != nil
    }

    private static func matches(_ regex: NSRegularExpression, in text: String) -> [Range<String.Index>] {
        regex.matches(in: text, range: NSRange(text.startIndex ..< text.endIndex, in: text))
            .compactMap { Range($0.range, in: text) }
    }
}
