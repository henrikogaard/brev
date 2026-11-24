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

/// Trusted receiving-server `authserv-id` boundary derived from an account's
/// configured IMAP host (#5).
///
/// Accounts whose IMAP host cannot establish a non-local receiver provenance
/// (empty, IP literal, loopback/`localhost`, or `.local`/`.internal` host)
/// produce `nil` so sign-in trust assessment fails closed rather than trusting
/// arbitrary sender-supplied `Authentication-Results` headers.
public struct IMAPSignInReceiverProvenance: Sendable, Equatable {
    /// Lowercased domain suffixes accepted for the receiving server's `authserv-id`
    /// and internal receiving `Received: ... by <host>` hops.
    public let trustedDomains: Set<String>

    /// Known provider boundaries where the IMAP hostname domain differs from the
    /// receiving MX's `Authentication-Results` `authserv-id` domain.
    private static let providerTrustGroups: [Set<String>] = [
        ["fastmail.com", "fastmail.fm", "messagingengine.com"],
        ["icloud.com", "me.com", "mac.com", "apple.com"],
        ["gmail.com", "googlemail.com", "google.com"],
        ["outlook.com", "office365.com", "hotmail.com", "live.com", "microsoft.com", "protection.outlook.com"],
        ["migadu.com"],
        ["mailbox.org"],
        ["yahoo.com", "yahoodns.net", "aol.com"],
        ["posteo.de", "posteo.net"],
        ["runbox.com"],
        ["zoho.com", "zoho.eu", "zohomail.com", "zohomail.eu"],
        ["gmx.net", "gmx.de", "gmx.com", "web.de", "ionos.com", "ionos.de", "1and1.com"],
        ["purelymail.com"],
        ["hey.com"],
        ["one.com"]
    ]

    private static let disallowedLocalSuffixes: Set<String> = [
        "localhost", "local", "internal", "home.arpa", "lan", "localdomain"
    ]

    /// Derives receiver provenance from a configured IMAP hostname.
    /// Returns `nil` when the host is empty, an IP literal, loopback, or local-only.
    public init?(incomingHost: String) {
        guard let normalized = AuthenticationResultsParser.normalizeDomain(incomingHost),
              !Self.isNonPublicHost(normalized),
              let orgDomain = AuthenticationResultsParser.organizationalDomain(of: normalized)
        else { return nil }

        var domains: Set<String> = [normalized, orgDomain]
        for group in Self.providerTrustGroups {
            if group.contains(where: { normalized == $0 || normalized.hasSuffix(".\($0)") }) {
                domains.formUnion(group)
            }
        }
        trustedDomains = domains
    }

    /// Creates a receiver provenance from explicit normalized trust domains.
    /// Returns `nil` when no valid non-local domains are supplied.
    public init?(trustedDomains: Set<String>) {
        var normalized: Set<String> = []
        for raw in trustedDomains {
            guard let domain = AuthenticationResultsParser.normalizeDomain(raw),
                  !Self.isNonPublicHost(domain),
                  AuthenticationResultsParser.organizationalDomain(of: domain) != nil
            else { continue }
            normalized.insert(domain)
        }
        guard !normalized.isEmpty else { return nil }
        self.trustedDomains = normalized
    }

    /// Returns `true` when `authservID` belongs to this account's trusted receiving boundary.
    public func matches(authservID: String) -> Bool {
        guard let candidate = AuthenticationResultsParser.normalizeDomain(authservID),
              !Self.isNonPublicHost(candidate)
        else { return false }
        return trustedDomains.contains { trusted in
            candidate == trusted || candidate.hasSuffix(".\(trusted)")
        }
    }

    private static func isNonPublicHost(_ normalizedHost: String) -> Bool {
        if normalizedHost.contains(":") { return true }
        let labels = normalizedHost.split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return true }
        // Reject IPv4 literals (for example 127.0.0.1 or 10.0.0.1).
        if labels.count == 4, labels.allSatisfy({ Int($0) != nil }) {
            return true
        }
        for suffix in disallowedLocalSuffixes
            where normalizedHost == suffix || normalizedHost.hasSuffix(".\(suffix)") {
            return true
        }
        return false
    }
}

/// One parsed RFC 8601 `resinfo` method result (for example `dkim=pass header.d=example.com`).
public struct AuthenticationResultsMethodResult: Sendable, Equatable {
    /// Lowercased authentication method name (for example `dmarc`, `dkim`, `spf`).
    public let method: String
    /// Optional method version suffix (for example `1` in `dkim/1=pass`).
    public let version: String?
    /// Lowercased authentication result keyword (for example `pass`, `fail`, `none`).
    public let result: String
    /// Parsed `ptype.property` / `reason` key-value pairs in header order (lowercased keys).
    public let properties: [Property]

    /// One key-value property inside an RFC 8601 method result segment.
    public struct Property: Sendable, Equatable {
        /// Lowercased property name (for example `header.from`, `header.d`, `smtp.mailfrom`).
        public let key: String
        /// Property value (unquoted if it was a quoted-string).
        public let value: String

        /// Creates a parsed property.
        public init(key: String, value: String) {
            self.key = key
            self.value = value
        }
    }

    /// Creates a parsed method result.
    public init(method: String, version: String? = nil, result: String, properties: [Property] = []) {
        self.method = method
        self.version = version
        self.result = result
        self.properties = properties
    }

    /// Returns all values recorded for `key` (case-insensitive).
    public func propertyValues(named key: String) -> [String] {
        let target = key.lowercased()
        return properties.compactMap { $0.key == target ? $0.value : nil }
    }
}

/// A parsed RFC 8601 `Authentication-Results` header field value.
public struct AuthenticationResultsHeader: Sendable, Equatable {
    /// Lowercased authentication service identifier (`authserv-id`).
    public let authservID: String
    /// Optional RFC 8601 `authres-version` integer.
    public let version: Int?
    /// Method results reported in this header (`[]` for `Authentication-Results: host; none`).
    public let results: [AuthenticationResultsMethodResult]

    /// Creates a parsed `Authentication-Results` header.
    public init(authservID: String, version: Int? = nil, results: [AuthenticationResultsMethodResult]) {
        self.authservID = authservID
        self.version = version
        self.results = results
    }
}

/// Standards-compliant RFC 8601 `Authentication-Results` and RFC 5322 header parser
/// used for generic IMAP sign-in code trust verification (#5).
public enum AuthenticationResultsParser {
    private enum LexToken: Equatable {
        case semicolon
        case word(String)
        case quoted(String)
    }

    /// Multi-label public suffixes under which sibling domains belong to different organizations.
    private static let multiLabelPublicSuffixes: Set<String> = [
        "ac.uk", "co.uk", "gov.uk", "ltd.uk", "me.uk", "net.uk", "nhs.uk", "org.uk", "plc.uk", "sch.uk",
        "com.au", "edu.au", "gov.au", "net.au", "org.au",
        "co.jp", "ne.jp", "or.jp", "ac.jp", "go.jp",
        "com.br", "net.br", "org.br", "gov.br",
        "co.nz", "net.nz", "org.nz", "govt.nz",
        "com.cn", "net.cn", "org.cn", "gov.cn",
        "com.tw", "net.tw", "org.tw", "com.hk", "com.sg", "com.my", "com.ph", "com.vn",
        "co.za", "co.in", "co.il", "co.kr", "co.id", "co.th",
        "com.mx", "com.ar", "com.tr", "com.es", "com.pl", "com.ua", "com.sa", "com.eg",
        "com.ng", "com.pk", "com.co", "com.pe", "com.ve",
        "priv.no", "fhs.no", "kommune.no", "herad.no", "vgs.no", "stat.no", "mil.no", "dep.no",
        "idrett.no", "museum.no",
        "github.io", "pages.dev", "appspot.com", "amazonaws.com", "azurewebsites.net",
        "herokuapp.com", "cloudfront.net", "firebaseapp.com", "web.app", "workers.dev",
        "netlify.app", "vercel.app"
    ]

    /// Parses top-level RFC 5322 header fields from raw headers or a full RFC 5322 message,
    /// stopping at the first blank line so body content cannot inject headers.
    /// - Parameter rawHeaders: Raw RFC 5322 header block or full message source.
    /// - Returns: Header `(name, value)` pairs in exact top-to-bottom order with RFC 5322 folding collapsed.
    public static func parseRawHeaderFields(_ rawHeaders: String) -> [(name: String, value: String)] {
        let normalized = rawHeaders
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var headers: [(name: String, value: String)] = []
        var currentName: String?
        var currentValue = ""

        func flush() {
            guard let name = currentName else { return }
            headers.append((name: name, value: currentValue.trimmingCharacters(in: .whitespaces)))
            currentName = nil
            currentValue = ""
        }

        for line in normalized.components(separatedBy: "\n") {
            if line.isEmpty {
                break
            }
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                if currentName != nil {
                    currentValue += " " + line.trimmingCharacters(in: .whitespaces)
                }
                continue
            }
            guard let colon = line.firstIndex(of: ":") else {
                flush()
                continue
            }
            let fieldName = String(line[..<colon])
            guard isValidHeaderFieldName(fieldName) else {
                flush()
                continue
            }
            flush()
            currentName = fieldName
            currentValue = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        flush()
        return headers
    }

    /// Parses a single RFC 8601 `Authentication-Results` header value.
    /// Returns `nil` when syntax is malformed (missing `;`, empty `authserv-id`, unclosed comment/quote, etc.).
    public static func parseHeader(_ value: String) -> AuthenticationResultsHeader? {
        guard let tokens = tokenize(unfold(value)) else { return nil }
        let segments = splitSegments(tokens)
        guard segments.count >= 2 else { return nil }
        guard let (authservID, version) = parseAuthservHeader(segments[0]) else { return nil }

        let resultSegments = Array(segments.dropFirst())
        if resultSegments.count == 1,
           resultSegments[0].count == 1,
           case .word(let token) = resultSegments[0][0],
           token.caseInsensitiveCompare("none") == .orderedSame {
            return AuthenticationResultsHeader(authservID: authservID, version: version, results: [])
        }

        var parsedResults: [AuthenticationResultsMethodResult] = []
        for (index, segment) in resultSegments.enumerated() {
            if segment.isEmpty {
                // Allow a harmless trailing semicolon only when at least one valid result preceded it.
                if index == resultSegments.count - 1, !parsedResults.isEmpty {
                    continue
                }
                return nil
            }
            guard let methodResult = parseMethodSegment(segment) else { return nil }
            parsedResults.append(methodResult)
        }
        guard !parsedResults.isEmpty else { return nil }
        return AuthenticationResultsHeader(authservID: authservID, version: version, results: parsedResults)
    }

    /// Extracts the normalized domain from a `From` header containing exactly one valid RFC 5322 mailbox.
    /// Rejects multiple addresses, group syntax, unclosed quotes/comments, and malformed domains.
    public static func singleMailboxDomain(from headerValue: String) -> String? {
        let unfolded = unfold(headerValue)
        guard !unfolded.isEmpty else { return nil }
        guard let stripped = stripCommentsAndCheckSingleAddress(unfolded) else { return nil }
        let addrSpec: String
        if let extracted = extractSingleAngleAddress(from: stripped) {
            addrSpec = extracted
        } else if stripped.contains("<") || stripped.contains(">") {
            return nil
        } else {
            let trimmed = stripped.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
            addrSpec = trimmed
        }
        return domainFromAddrSpec(addrSpec)
    }

    /// Returns `true` when `authenticatedDomain` aligns with `fromDomain` under DMARC relaxed
    /// organizational-domain alignment while preventing false alignment across public suffixes.
    public static func domainsAlign(_ authenticatedDomain: String, with fromDomain: String) -> Bool {
        guard let auth = normalizeDomain(authenticatedDomain),
              let from = normalizeDomain(fromDomain)
        else { return false }
        if auth == from { return true }
        guard let authOrg = organizationalDomain(of: auth),
              let fromOrg = organizationalDomain(of: from)
        else { return false }
        return authOrg == fromOrg
    }

    /// Extracts the receiving hostname (`by <host>`) from an RFC 5322 `Received` header value.
    /// Returns `nil` when malformed or absent.
    static func receivedByHost(from headerValue: String) -> String? {
        guard let tokens = tokenize(unfold(headerValue)) else { return nil }
        let prefixTokens = tokens.prefix { $0 != .semicolon }
        var index = prefixTokens.startIndex
        while index < prefixTokens.endIndex {
            if case .word(let keyword) = prefixTokens[index],
               keyword.caseInsensitiveCompare("by") == .orderedSame {
                let next = prefixTokens.index(after: index)
                guard next < prefixTokens.endIndex,
                      let hostToken = tokenString(prefixTokens[next])
                else { return nil }
                return normalizeDomain(hostToken)
            }
            index = prefixTokens.index(after: index)
        }
        return nil
    }

    /// Normalizes a domain or `local@domain` property value to a lowercased domain name.
    static func extractDomain(fromPropertyValue value: String, allowsLocalPart: Bool) -> String? {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("@") {
            guard allowsLocalPart else { return nil }
            let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            return normalizeDomain(String(parts[1]))
        }
        return normalizeDomain(trimmed)
    }

    // MARK: - Private RFC 8601 lexer & parser

    private static func isValidHeaderFieldName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 33 && scalar.value <= 126 && scalar != ":"
        }
    }

    private static func unfold(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        var inWhitespaceRun = false
        for scalar in value.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                inWhitespaceRun = true
            } else {
                if inWhitespaceRun, !result.isEmpty { result.append(" ") }
                result.unicodeScalars.append(scalar)
                inWhitespaceRun = false
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tokenize(_ input: String) -> [LexToken]? {
        var tokens: [LexToken] = []
        var index = input.startIndex
        let end = input.endIndex

        while index < end {
            let char = input[index]
            if char == " " || char == "\t" {
                index = input.index(after: index)
                continue
            }
            if char == "(" {
                guard let afterComment = skipComment(in: input, from: index) else { return nil }
                index = afterComment
                continue
            }
            if char == ")" {
                return nil
            }
            if char == ";" {
                tokens.append(.semicolon)
                index = input.index(after: index)
                continue
            }
            if char == "\"" {
                guard let (quoted, nextIndex) = readQuotedString(in: input, from: index) else { return nil }
                tokens.append(.quoted(quoted))
                index = nextIndex
                continue
            }
            var wordEnd = index
            while wordEnd < end {
                let c = input[wordEnd]
                if c == " " || c == "\t" || c == ";" || c == "(" || c == ")" || c == "\"" {
                    break
                }
                wordEnd = input.index(after: wordEnd)
            }
            tokens.append(.word(String(input[index ..< wordEnd])))
            index = wordEnd
        }
        return tokens
    }

    private static func skipComment(in input: String, from start: String.Index) -> String.Index? {
        var index = input.index(after: start)
        var depth = 1
        var escaped = false
        while index < input.endIndex, depth > 0 {
            let c = input[index]
            if escaped {
                escaped = false
            } else if c == "\\" {
                escaped = true
            } else if c == "(" {
                depth += 1
            } else if c == ")" {
                depth -= 1
            }
            index = input.index(after: index)
        }
        return depth == 0 && !escaped ? index : nil
    }

    private static func readQuotedString(in input: String, from start: String.Index) -> (String, String.Index)? {
        var index = input.index(after: start)
        var value = ""
        var escaped = false
        while index < input.endIndex {
            let c = input[index]
            if escaped {
                value.append(c)
                escaped = false
            } else if c == "\\" {
                escaped = true
            } else if c == "\"" {
                return (value, input.index(after: index))
            } else {
                value.append(c)
            }
            index = input.index(after: index)
        }
        return nil
    }

    private static func splitSegments(_ tokens: [LexToken]) -> [[LexToken]] {
        var segments: [[LexToken]] = []
        var current: [LexToken] = []
        for token in tokens {
            if token == .semicolon {
                segments.append(current)
                current = []
            } else {
                current.append(token)
            }
        }
        segments.append(current)
        return segments
    }

    private static func parseAuthservHeader(_ tokens: [LexToken]) -> (String, Int?)? {
        guard !tokens.isEmpty, tokens.count <= 2 else { return nil }
        // RFC 8601 §2.2 permits authserv-id as either a token or a quoted-string.
        guard let rawHost = tokenString(tokens[0])?.trimmingCharacters(in: .whitespaces),
              !rawHost.isEmpty,
              !rawHost.contains("="),
              !rawHost.contains(where: \.isWhitespace)
        else { return nil }
        var version: Int?
        if tokens.count == 2 {
            guard case .word(let rawVersion) = tokens[1],
                  let parsed = Int(rawVersion), parsed >= 1
            else { return nil }
            version = parsed
        }
        return (rawHost.lowercased(), version)
    }

    private static func parseMethodSegment(_ tokens: [LexToken]) -> AuthenticationResultsMethodResult? {
        guard let pairs = parseKeyValuePairs(tokens), let first = pairs.first else { return nil }
        let methodSpec = first.key.lowercased()
        let methodName: String
        let methodVersion: String?
        if let slash = methodSpec.firstIndex(of: "/") {
            methodName = String(methodSpec[..<slash])
            let ver = String(methodSpec[methodSpec.index(after: slash)...])
            guard !ver.isEmpty else { return nil }
            methodVersion = ver
        } else {
            methodName = methodSpec
            methodVersion = nil
        }
        guard !methodName.isEmpty, !first.value.isEmpty else { return nil }
        let properties = pairs.dropFirst().map {
            AuthenticationResultsMethodResult.Property(key: $0.key.lowercased(), value: $0.value)
        }
        return AuthenticationResultsMethodResult(
            method: methodName,
            version: methodVersion,
            result: first.value.lowercased(),
            properties: properties
        )
    }

    private static func parseKeyValuePairs(_ tokens: [LexToken]) -> [(key: String, value: String)]? {
        var pairs: [(key: String, value: String)] = []
        var index = 0
        while index < tokens.count {
            guard case .word(var lhs) = tokens[index] else { return nil }
            index += 1

            // Merge CFWS-separated dotted property names such as `header . from`.
            while !lhs.contains("="), index < tokens.count {
                if lhs.hasSuffix("."), case .word(let next) = tokens[index] {
                    lhs += next
                    index += 1
                } else if case .word(let next) = tokens[index], next.hasPrefix(".") {
                    lhs += next
                    index += 1
                } else {
                    break
                }
            }

            if let eq = lhs.firstIndex(of: "=") {
                let key = String(lhs[..<eq])
                let rhs = String(lhs[lhs.index(after: eq)...])
                guard !key.isEmpty else { return nil }
                if !rhs.isEmpty {
                    pairs.append((key: key, value: rhs))
                } else {
                    guard index < tokens.count, let value = tokenString(tokens[index]) else { return nil }
                    index += 1
                    pairs.append((key: key, value: value))
                }
            } else {
                guard index < tokens.count, case .word(let eqToken) = tokens[index], eqToken.hasPrefix("=") else {
                    return nil
                }
                index += 1
                let trailing = String(eqToken.dropFirst())
                if !trailing.isEmpty {
                    pairs.append((key: lhs, value: trailing))
                } else {
                    guard index < tokens.count, let value = tokenString(tokens[index]) else { return nil }
                    index += 1
                    pairs.append((key: lhs, value: value))
                }
            }
        }
        return pairs
    }

    private static func tokenString(_ token: LexToken) -> String? {
        switch token {
        case .word(let value), .quoted(let value):
            value
        case .semicolon:
            nil
        }
    }

    // MARK: - Private From-header & domain helpers

    private static func stripCommentsAndCheckSingleAddress(_ input: String) -> String? {
        var output = ""
        var index = input.startIndex
        var inQuotes = false
        var escaped = false

        while index < input.endIndex {
            let c = input[index]
            if inQuotes {
                output.append(c)
                if escaped {
                    escaped = false
                } else if c == "\\" {
                    escaped = true
                } else if c == "\"" {
                    inQuotes = false
                }
                index = input.index(after: index)
                continue
            }
            if c == "(" {
                guard let afterComment = skipComment(in: input, from: index) else { return nil }
                output.append(" ")
                index = afterComment
                continue
            }
            if c == ")" {
                return nil
            }
            if c == "\"" {
                inQuotes = true
                output.append(c)
                index = input.index(after: index)
                continue
            }
            // Unquoted comma or group delimiters indicate multiple addresses or group syntax.
            if c == "," || c == ":" || c == ";" {
                return nil
            }
            output.append(c)
            index = input.index(after: index)
        }
        return inQuotes ? nil : output
    }

    private static func extractSingleAngleAddress(from stripped: String) -> String? {
        var openIndex: String.Index?
        var closeIndex: String.Index?
        var inQuotes = false
        var escaped = false
        var index = stripped.startIndex

        while index < stripped.endIndex {
            let c = stripped[index]
            if inQuotes {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inQuotes = false }
            } else if c == "\"" {
                inQuotes = true
            } else if c == "<" {
                guard openIndex == nil else { return nil }
                openIndex = index
            } else if c == ">" {
                guard openIndex != nil, closeIndex == nil else { return nil }
                closeIndex = index
            }
            index = stripped.index(after: index)
        }

        guard let open = openIndex, let close = closeIndex else { return nil }
        let trailing = stripped[stripped.index(after: close)...].trimmingCharacters(in: .whitespaces)
        guard trailing.isEmpty else { return nil }
        let interior = stripped[stripped.index(after: open) ..< close].trimmingCharacters(in: .whitespaces)
        guard !interior.isEmpty, !interior.contains(where: \.isWhitespace) else { return nil }
        return interior
    }

    private static func domainFromAddrSpec(_ addrSpec: String) -> String? {
        let parts = addrSpec.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return nil }
        return normalizeDomain(String(parts[1]))
    }

    static func normalizeDomain(_ raw: String) -> String? {
        var domain = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if domain.hasSuffix(".") {
            domain.removeLast()
        }
        guard !domain.isEmpty else { return nil }
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return nil }
        for label in labels {
            guard !label.isEmpty,
                  !label.hasPrefix("-"),
                  !label.hasSuffix("-"),
                  label.unicodeScalars.allSatisfy({ scalar in
                      (scalar.value >= 97 && scalar.value <= 122)
                          || (scalar.value >= 48 && scalar.value <= 57)
                          || scalar == "-"
                          || scalar.value > 127
                  })
            else { return nil }
        }
        return domain
    }

    static func organizationalDomain(of normalizedDomain: String) -> String? {
        let labels = normalizedDomain.split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return nil }
        let lastTwo = labels.suffix(2).joined(separator: ".")
        if multiLabelPublicSuffixes.contains(lastTwo) {
            guard labels.count >= 3 else { return nil }
            return labels.suffix(3).joined(separator: ".")
        }
        return lastTwo
    }
}

/// Evaluates raw RFC 5322 headers for generic IMAP sign-in code verification (#5).
///
/// Inspects only the top-most `Authentication-Results` header at the receiving
/// server's trust boundary (`receiverProvenance`), ensuring no external
/// `Received:` hop precedes it and rejecting forged/foreign `authserv-id`
/// values. Requires:
/// 1. Top-most `Authentication-Results` matches `receiverProvenance` with no
///    external `Received:` hop above it and no conflicting lower header from the
///    same receiving boundary.
/// 2. Single valid RFC 5322 `From` header with one mailbox domain.
/// 3. Exactly one `dmarc=pass` result whose `header.from` matches `From` exactly.
/// 4. At least one aligned `dkim=pass` (`header.d` / `header.i`) or aligned `spf=pass`
///    (`smtp.mailfrom` / `smtp.helo`) in the same top-most header.
public enum AuthenticationResultsSignInTrustAssessor {
    /// Evaluates sign-in trust from a raw RFC 5322 header block or message source
    /// against the account's established `receiverProvenance`.
    public static func assess(
        rawHeaders: String,
        receiverProvenance: IMAPSignInReceiverProvenance
    ) -> SignInTrustAssessment {
        assess(
            headers: AuthenticationResultsParser.parseRawHeaderFields(rawHeaders),
            receiverProvenance: receiverProvenance
        )
    }

    /// Evaluates sign-in trust from top-to-bottom RFC 5322 header fields
    /// against the account's established `receiverProvenance`.
    public static func assess(
        headers: [(name: String, value: String)],
        receiverProvenance: IMAPSignInReceiverProvenance
    ) -> SignInTrustAssessment {
        guard let topmostIndex = headers.firstIndex(where: {
            $0.name.caseInsensitiveCompare("Authentication-Results") == .orderedSame
        }) else {
            return .unavailable(.noTrustedHeader)
        }

        // Only trust an Authentication-Results header at the top receiving
        // boundary: any external Received hop above it means the header was
        // preserved from an earlier hop or injected before receipt.
        for preceding in headers[..<topmostIndex]
            where preceding.name.caseInsensitiveCompare("Received") == .orderedSame {
            guard let byHost = AuthenticationResultsParser.receivedByHost(from: preceding.value),
                  receiverProvenance.matches(authservID: byHost)
            else {
                return .unavailable(.noTrustedHeader)
            }
        }

        guard let topmost = AuthenticationResultsParser.parseHeader(headers[topmostIndex].value) else {
            return .unavailable(.malformedHeader)
        }
        guard receiverProvenance.matches(authservID: topmost.authservID) else {
            return .unavailable(.noTrustedHeader)
        }

        // Reject conflicting lower headers claiming the same receiving trust boundary.
        let lowerAuthHeaders = headers[headers.index(after: topmostIndex)...].filter {
            $0.name.caseInsensitiveCompare("Authentication-Results") == .orderedSame
        }
        for lowerRaw in lowerAuthHeaders.map(\.value) {
            guard let lower = AuthenticationResultsParser.parseHeader(lowerRaw) else {
                continue
            }
            if lower.authservID == topmost.authservID || receiverProvenance.matches(authservID: lower.authservID),
               lower.results.contains(where: { $0.method == "dmarc" }) {
                return .unavailable(.conflictingTrustedHeaders)
            }
        }

        let dmarcSegments = topmost.results.filter { $0.method == "dmarc" }
        let strayDMARCProperties = topmost.results.flatMap(\.properties).filter { $0.key == "dmarc" }
        if dmarcSegments.count + strayDMARCProperties.count > 1 {
            return .unavailable(.duplicateDMARC)
        }
        guard let dmarc = dmarcSegments.first else {
            return .unavailable(.missingDMARC)
        }
        guard dmarc.result == "pass" else {
            return .unavailable(.dmarcNotPass)
        }
        let headerFromValues = dmarc.propertyValues(named: "header.from")
        guard headerFromValues.count == 1,
              let headerFromDomain = AuthenticationResultsParser.extractDomain(
                  fromPropertyValue: headerFromValues[0],
                  allowsLocalPart: true
              )
        else {
            return .unavailable(.malformedHeader)
        }

        let fromHeaders = headers.filter { $0.name.caseInsensitiveCompare("From") == .orderedSame }
        guard fromHeaders.count == 1,
              let fromDomain = AuthenticationResultsParser.singleMailboxDomain(from: fromHeaders[0].value)
        else {
            return .unavailable(.malformedFrom)
        }
        guard fromDomain == headerFromDomain else {
            return .unavailable(.fromMismatch)
        }

        guard hasAlignedPassingMechanism(in: topmost, fromDomain: fromDomain) else {
            return .unavailable(.missingAlignedMechanism)
        }
        return .pass(fromDomain: fromDomain)
    }

    private static func hasAlignedPassingMechanism(
        in header: AuthenticationResultsHeader,
        fromDomain: String
    ) -> Bool {
        for entry in header.results where entry.result == "pass" {
            if entry.method == "dkim",
               let domain = dkimSigningDomain(for: entry),
               AuthenticationResultsParser.domainsAlign(domain, with: fromDomain) {
                return true
            }
            if entry.method == "spf",
               let domain = spfAuthenticatedDomain(for: entry),
               AuthenticationResultsParser.domainsAlign(domain, with: fromDomain) {
                return true
            }
        }
        return false
    }

    private static func dkimSigningDomain(for entry: AuthenticationResultsMethodResult) -> String? {
        let dValues = entry.propertyValues(named: "header.d")
        if !dValues.isEmpty {
            guard dValues.count == 1 else { return nil }
            return AuthenticationResultsParser.extractDomain(fromPropertyValue: dValues[0], allowsLocalPart: false)
        }
        let iValues = entry.propertyValues(named: "header.i")
        guard iValues.count == 1, iValues[0].contains("@") else { return nil }
        return AuthenticationResultsParser.extractDomain(fromPropertyValue: iValues[0], allowsLocalPart: true)
    }

    private static func spfAuthenticatedDomain(for entry: AuthenticationResultsMethodResult) -> String? {
        let mailFromValues = entry.propertyValues(named: "smtp.mailfrom")
        if !mailFromValues.isEmpty {
            guard mailFromValues.count == 1 else { return nil }
            if let domain = AuthenticationResultsParser.extractDomain(
                fromPropertyValue: mailFromValues[0],
                allowsLocalPart: true
            ) {
                return domain
            }
        }
        let heloValues = entry.propertyValues(named: "smtp.helo")
        guard heloValues.count == 1 else { return nil }
        return AuthenticationResultsParser.extractDomain(fromPropertyValue: heloValues[0], allowsLocalPart: false)
    }
}
