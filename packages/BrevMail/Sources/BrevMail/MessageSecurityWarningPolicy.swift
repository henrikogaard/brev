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

struct MessageSecurityAnalysis: Equatable, Sendable {
    let warnings: [MessageSecurityWarning]
    let linkWarnings: [MessageSecurityLinkWarning]

    static let empty = MessageSecurityAnalysis(warnings: [], linkWarnings: [])

    var hasWarnings: Bool {
        !warnings.isEmpty || !linkWarnings.isEmpty
    }

    var summary: String? {
        hasWarnings
            ? "Sender or link details look unusual. Check the highlighted details before trusting this message."
            : nil
    }

    func warning(for url: URL) -> MessageSecurityLinkWarning? {
        linkWarnings.first { $0.matches(url) }
    }
}

struct MessageSecurityWarning: Equatable, Sendable {
    let kind: Kind
    let title: String
    let message: String

    enum Kind: Hashable, Sendable {
        case displayNameDomainMismatch(displayedDomain: String, senderDomain: String)
        case replyToDomainMismatch(senderDomain: String, replyToDomain: String)
        case deceptiveLink(displayedDomain: String, destinationDomain: String)
        case internationalizedLink(destinationDomain: String)
    }
}

enum MessageSecurityLinkWarningReason: Equatable, Sendable {
    case deceptiveText
    case internationalizedDomain
}

struct MessageSecurityLinkWarning: Equatable, Sendable {
    let url: URL
    let displayedHost: String?
    let destinationHost: String
    let reason: MessageSecurityLinkWarningReason

    var confirmationTitle: String {
        "Open suspicious link?"
    }

    var confirmationMessage: String {
        switch reason {
        case .deceptiveText:
            if let displayedHost {
                return "This link is shown as \(displayedHost), but it opens \(destinationHost)."
            }
            return "This link opens \(destinationHost)."
        case .internationalizedDomain:
            return "\(destinationHost) uses an internationalized domain spelling. Check it carefully before opening."
        }
    }

    var openButtonTitle: String {
        "Open \(destinationHost)"
    }

    func matches(_ other: URL) -> Bool {
        normalizedURLString(url) == normalizedURLString(other)
    }

    private func normalizedURLString(_ value: URL) -> String {
        value.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum MessageSecurityWarningPolicy {
    /// Analysis scans the entire body for links and the reading pane asks
    /// for it on every render, so results are memoized on the inputs.
    private final class CachedAnalysis {
        let analysis: MessageSecurityAnalysis
        init(_ analysis: MessageSecurityAnalysis) { self.analysis = analysis }
    }

    private static let analysisCache: NSCache<NSString, CachedAnalysis> = {
        let cache = NSCache<NSString, CachedAnalysis>()
        cache.countLimit = 64
        return cache
    }()

    static func analyze(
        header: MessageHeader,
        bodyHTML: String?,
        replyTo: [Correspondent] = []
    ) -> MessageSecurityAnalysis {
        let replyToKey = replyTo.map { "\($0.name ?? "")<\($0.email)>" }.joined(separator: ",")
        let key = "\(header.id)\u{1F}\(header.from.name ?? "")<\(header.from.email)>"
            + "\u{1F}\(replyToKey)\u{1F}\(bodyHTML ?? "")" as NSString
        if let cached = analysisCache.object(forKey: key) {
            return cached.analysis
        }
        let analysis = computeAnalysis(header: header, bodyHTML: bodyHTML, replyTo: replyTo)
        analysisCache.setObject(CachedAnalysis(analysis), forKey: key)
        return analysis
    }

    private static func computeAnalysis(
        header: MessageHeader,
        bodyHTML: String?,
        replyTo: [Correspondent]
    ) -> MessageSecurityAnalysis {
        var warnings: [MessageSecurityWarning] = []
        var linkWarningResults: [MessageSecurityLinkWarning] = []
        var seenKinds: Set<MessageSecurityWarning.Kind> = []

        if let warning = displayNameDomainWarning(for: header.from),
           seenKinds.insert(warning.kind).inserted {
            warnings.append(warning)
        }

        if let warning = replyToDomainWarning(from: header.from, replyTo: replyTo),
           seenKinds.insert(warning.kind).inserted {
            warnings.append(warning)
        }

        for linkWarning in linkWarnings(in: bodyHTML) {
            linkWarningResults.append(linkWarning)
            let warning = warning(for: linkWarning)
            if seenKinds.insert(warning.kind).inserted {
                warnings.append(warning)
            }
        }

        guard !warnings.isEmpty || !linkWarningResults.isEmpty else { return .empty }
        return MessageSecurityAnalysis(warnings: warnings, linkWarnings: linkWarningResults)
    }

    private static func displayNameDomainWarning(for sender: Correspondent) -> MessageSecurityWarning? {
        guard let senderDomain = domain(fromEmail: sender.email),
              let displayName = sender.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !displayName.isEmpty
        else { return nil }

        guard let displayedDomain = domains(in: displayName).first(where: {
            !domainsAreRelated($0, senderDomain)
        }) else { return nil }

        return MessageSecurityWarning(
            kind: .displayNameDomainMismatch(
                displayedDomain: displayedDomain,
                senderDomain: senderDomain
            ),
            title: "Sender name and address differ",
            message: "The sender name mentions \(displayedDomain), but the message came from \(senderDomain)."
        )
    }

    private static func replyToDomainWarning(
        from sender: Correspondent,
        replyTo: [Correspondent]
    ) -> MessageSecurityWarning? {
        guard let senderDomain = domain(fromEmail: sender.email) else { return nil }
        guard let replyToDomain = replyTo
            .compactMap({ domain(fromEmail: $0.email) })
            .first(where: { !domainsAreRelated($0, senderDomain) })
        else { return nil }

        return MessageSecurityWarning(
            kind: .replyToDomainMismatch(
                senderDomain: senderDomain,
                replyToDomain: replyToDomain
            ),
            title: "Replies go somewhere else",
            message: "Replies would go to \(replyToDomain), not \(senderDomain)."
        )
    }

    private static func linkWarnings(in html: String?) -> [MessageSecurityLinkWarning] {
        guard let html, !html.isEmpty else { return [] }
        return htmlLinks(in: html).compactMap { link in
            guard let destinationHost = host(from: link.url) else { return nil }
            if isInternationalizedDomain(destinationHost) {
                return MessageSecurityLinkWarning(
                    url: link.url,
                    displayedHost: nil,
                    destinationHost: destinationHost,
                    reason: .internationalizedDomain
                )
            }
            // Warn if ANY domain shown in the label is unrelated to where the
            // link actually goes. Checking only one displayed host let an
            // attacker plant a hidden URL matching the destination to suppress
            // the warning while the visible text showed a different domain.
            guard let deceptiveHost = displayedHosts(from: link.label)
                .first(where: { !domainsAreRelated($0, destinationHost) })
            else { return nil }
            return MessageSecurityLinkWarning(
                url: link.url,
                displayedHost: deceptiveHost,
                destinationHost: destinationHost,
                reason: .deceptiveText
            )
        }
    }

    private static func warning(for linkWarning: MessageSecurityLinkWarning) -> MessageSecurityWarning {
        switch linkWarning.reason {
        case .deceptiveText:
            return MessageSecurityWarning(
                kind: .deceptiveLink(
                    displayedDomain: linkWarning.displayedHost ?? "unknown",
                    destinationDomain: linkWarning.destinationHost
                ),
                title: "Link destination differs",
                message: linkWarning.confirmationMessage
            )
        case .internationalizedDomain:
            return MessageSecurityWarning(
                kind: .internationalizedLink(destinationDomain: linkWarning.destinationHost),
                title: "Link uses a look-alike domain spelling",
                message: linkWarning.confirmationMessage
            )
        }
    }

    private struct HTMLLink {
        let url: URL
        let label: String
    }

    // `attrScan` treats quoted attribute values as atomic so a `>` inside an
    // earlier attribute (e.g. `<a title="x>y" href="https://evil.com">`)
    // cannot end the tag scan before `href` — a plain `[^>]*` did, dropping
    // the link entirely and suppressing the deceptive-link phishing warning.
    private static let anchorRegex: NSRegularExpression? = {
        let attrScan = #"(?:[^>"']|"[^"]*"|'[^']*')"#
        return try? NSRegularExpression(
            pattern: #"<a\b\#(attrScan)*?\bhref\s*=\s*(?:"([^"]+)"|'([^']+)'|([^'">\s]+))\#(attrScan)*>(.*?)</a>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
    }()

    private static func htmlLinks(in html: String) -> [HTMLLink] {
        guard let regex = anchorRegex else { return [] }

        let range = NSRange(html.startIndex ..< html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let rawHref = firstCapturedString(in: match, source: html, ranges: [1, 2, 3]),
                  let url = remoteURL(from: rawHref),
                  let labelRange = Range(match.range(at: 4), in: html)
            else { return nil }
            return HTMLLink(
                url: url,
                label: plainText(fromHTMLFragment: String(html[labelRange]))
            )
        }
    }

    private static func firstCapturedString(
        in match: NSTextCheckingResult,
        source: String,
        ranges: [Int]
    ) -> String? {
        for index in ranges {
            guard index < match.numberOfRanges,
                  let range = Range(match.range(at: index), in: source)
            else { continue }
            return String(source[range])
        }
        return nil
    }

    private static func remoteURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw: String
        if trimmed.hasPrefix("//") {
            raw = "https:\(trimmed)"
        } else {
            raw = trimmed
        }
        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }

    /// Every distinct domain a reader could see in the link's label: the hosts
    /// of any embedded URLs AND any bare domains, de-duplicated in order. Used to
    /// flag a mismatch against the real destination even when a hidden URL is
    /// planted alongside a deceptive bare domain.
    private static func displayedHosts(from label: String) -> [String] {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var seen = Set<String>()
        return (urlHosts(in: trimmed) + domains(in: trimmed)).filter { seen.insert($0).inserted }
    }

    private static func urlHosts(in text: String) -> [String] {
        let pattern = #"https?://[^\s<>"']+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            return remoteURL(from: String(text[matchRange])).flatMap(host(from:))
        }
    }

    private static func plainText(fromHTMLFragment fragment: String) -> String {
        fragment
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    private static func domain(fromEmail email: String) -> String? {
        guard let atIndex = email.lastIndex(of: "@") else { return nil }
        return normalizeDomain(String(email[email.index(after: atIndex)...]))
    }

    private static func host(from url: URL) -> String? {
        if let rawHost = rawHost(from: url.absoluteString) {
            return normalizeDomain(rawHost)
        }
        if let host = URLComponents(url: url, resolvingAgainstBaseURL: false)?.host {
            return normalizeDomain(host)
        }
        return url.host.flatMap(normalizeDomain)
    }

    private static func rawHost(from urlString: String) -> String? {
        let pattern = #"^[a-z][a-z0-9+.-]*://([^/?#]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(urlString.startIndex ..< urlString.endIndex, in: urlString)
        guard let match = regex.firstMatch(in: urlString, range: range),
              match.numberOfRanges > 1,
              let authorityRange = Range(match.range(at: 1), in: urlString)
        else { return nil }

        var authority = String(urlString[authorityRange])
        if let atIndex = authority.lastIndex(of: "@") {
            authority = String(authority[authority.index(after: atIndex)...])
        }
        if authority.hasPrefix("["),
           let closeIndex = authority.firstIndex(of: "]") {
            return String(authority[authority.startIndex ... closeIndex])
        }
        if let colonIndex = authority.firstIndex(of: ":") {
            authority = String(authority[..<colonIndex])
        }
        return authority
    }

    private static func domains(in text: String) -> [String] {
        let pattern = #"(?i)\b(?:[a-z0-9._%+-]+@)?([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        var seen: Set<String> = []
        var result: [String] = []
        for match in regex.matches(in: text, range: range) {
            guard match.numberOfRanges > 1,
                  let domainRange = Range(match.range(at: 1), in: text),
                  let domain = normalizeDomain(String(text[domainRange])),
                  hasPlausibleTLD(domain),
                  seen.insert(domain).inserted
            else { continue }
            result.append(domain)
        }
        return result
    }

    /// True when `domain`'s final label looks like a real TLD: 2+ characters with
    /// at least one letter. This keeps version numbers ("2.3.1"), prices
    /// ("19.99"), and bare IPv4 literals out of the bare-text "displayed host"
    /// set — otherwise legitimate anchor text containing such a token raised a
    /// false deceptive-link warning. Real URL hosts come from `urlHosts(in:)`,
    /// which is unaffected, so genuine IP/punycode destinations are still checked.
    private static func hasPlausibleTLD(_ domain: String) -> Bool {
        guard let lastLabel = domain.split(separator: ".").last else { return false }
        return lastLabel.count >= 2 && lastLabel.contains { $0.isASCII && $0.isLetter }
    }

    private static func normalizeDomain(_ domain: String) -> String? {
        let trimmed = domain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func domainsAreRelated(_ lhs: String, _ rhs: String) -> Bool {
        guard let lhs = normalizeDomain(lhs),
              let rhs = normalizeDomain(rhs)
        else { return false }
        return lhs == rhs
            || lhs.hasSuffix(".\(rhs)")
            || rhs.hasSuffix(".\(lhs)")
    }

    private static func isInternationalizedDomain(_ host: String) -> Bool {
        host
            .split(separator: ".")
            .contains { $0.lowercased().hasPrefix("xn--") }
    }
}
