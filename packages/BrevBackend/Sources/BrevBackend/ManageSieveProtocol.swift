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

// MARK: - ManageSieve protocol (RFC 5804)

/// Server capabilities announced in the ManageSieve greeting (RFC 5804 §1.7).
public struct ManageSieveCapabilities: Sendable, Hashable {
    /// SASL mechanisms the server offers (upper-cased, e.g. `PLAIN`).
    public let saslMechanisms: Set<String>
    /// Sieve extensions the server supports (lower-cased, e.g. `fileinto`).
    public let sieveExtensions: Set<String>
    /// Whether the server advertised `STARTTLS`.
    public let supportsStartTLS: Bool
    /// The `IMPLEMENTATION` string, if announced.
    public let implementation: String?

    public init(
        saslMechanisms: Set<String> = [],
        sieveExtensions: Set<String> = [],
        supportsStartTLS: Bool = false,
        implementation: String? = nil
    ) {
        self.saslMechanisms = saslMechanisms
        self.sieveExtensions = sieveExtensions
        self.supportsStartTLS = supportsStartTLS
        self.implementation = implementation
    }

    /// Parses the capability lines that precede the final `OK` of a greeting or
    /// `CAPABILITY` response. Each capability is `"NAME" "value"` or a bare
    /// `"NAME"` (e.g. `STARTTLS`).
    public static func parse(_ lines: [String]) -> ManageSieveCapabilities {
        var sasl: Set<String> = []
        var extensions: Set<String> = []
        var startTLS = false
        var implementation: String?

        for line in lines {
            let tokens = quotedTokens(in: line)
            guard let name = tokens.first?.uppercased() else { continue }
            let value = tokens.count > 1 ? tokens[1] : ""
            switch name {
            case "SASL":
                sasl.formUnion(value.split(whereSeparator: \.isWhitespace).map { $0.uppercased() })
            case "SIEVE":
                extensions.formUnion(value.split(whereSeparator: \.isWhitespace).map { $0.lowercased() })
            case "STARTTLS":
                startTLS = true
            case "IMPLEMENTATION":
                implementation = value.isEmpty ? nil : value
            default:
                break
            }
        }
        return ManageSieveCapabilities(
            saslMechanisms: sasl,
            sieveExtensions: extensions,
            supportsStartTLS: startTLS,
            implementation: implementation
        )
    }

    /// Splits a line into its double-quoted tokens, or whitespace tokens when
    /// unquoted (`STARTTLS`).
    static func quotedTokens(in line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        for character in line {
            if character == "\"" {
                if inQuotes { tokens.append(current); current = "" }
                inQuotes.toggle()
            } else if inQuotes {
                current.append(character)
            }
        }
        if tokens.isEmpty {
            // No quotes — treat the whole bare line as a single token.
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { tokens.append(trimmed) }
        }
        return tokens
    }
}

// MARK: - Response

public enum ManageSieveResponseStatus: String, Sendable, Hashable {
    case ok = "OK"
    case no = "NO"
    case bye = "BYE"
}

/// A ManageSieve command result line (`OK`, `NO`, or `BYE`), with an optional
/// machine-readable response code in parentheses and a human-readable message.
public struct ManageSieveResponse: Sendable, Hashable {
    public let status: ManageSieveResponseStatus
    public let code: String?
    public let message: String?

    public init(status: ManageSieveResponseStatus, code: String? = nil, message: String? = nil) {
        self.status = status
        self.code = code
        self.message = message
    }

    public var isOK: Bool { status == .ok }

    /// Parses a single result line, e.g. `OK`, `NO "quota exceeded"`, or
    /// `NO (QUOTA/MAXSCRIPTS) "Too many scripts"`. Returns `nil` if the line is
    /// not a recognized result (i.e. it is intermediate data).
    public static func parse(_ rawLine: String) -> ManageSieveResponse? {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = line.uppercased()
        let status: ManageSieveResponseStatus
        if upper == "OK" || upper.hasPrefix("OK ") || upper.hasPrefix("OK(") {
            status = .ok
        } else if upper.hasPrefix("NO"), upper == "NO" || upper.hasPrefix("NO ") || upper.hasPrefix("NO(") {
            status = .no
        } else if upper.hasPrefix("BYE"), upper == "BYE" || upper.hasPrefix("BYE ") || upper.hasPrefix("BYE(") {
            status = .bye
        } else {
            return nil
        }

        var remainder = String(line.dropFirst(status.rawValue.count))
            .trimmingCharacters(in: .whitespaces)

        var code: String?
        if remainder.hasPrefix("("), let close = remainder.firstIndex(of: ")") {
            code = String(remainder[remainder.index(after: remainder.startIndex) ..< close])
            remainder = String(remainder[remainder.index(after: close)...])
                .trimmingCharacters(in: .whitespaces)
        }

        var message: String?
        if let parsed = ManageSieveCapabilities.quotedTokens(in: remainder).first, !parsed.isEmpty {
            message = parsed
        }
        return ManageSieveResponse(status: status, code: code, message: message)
    }
}

// MARK: - Commands

/// Builds RFC 5804 ManageSieve command strings.
public enum ManageSieveCommand {
    /// `AUTHENTICATE "PLAIN" "<base64>"` carrying `\0username\0password`.
    public static func authenticatePlain(username: String, password: String) -> String {
        let payload = Data("\u{0}\(username)\u{0}\(password)".utf8).base64EncodedString()
        return "AUTHENTICATE \"PLAIN\" \"\(payload)\""
    }

    public static func listScripts() -> String { "LISTSCRIPTS" }
    public static func logout() -> String { "LOGOUT" }
    public static func setActive(name: String) -> String { "SETACTIVE \(quote(name))" }
    public static func deleteScript(name: String) -> String { "DELETESCRIPT \(quote(name))" }
    public static func getScript(name: String) -> String { "GETSCRIPT \(quote(name))" }

    /// The first line of a `PUTSCRIPT`, using a non-synchronizing literal
    /// (`{len+}`) for the script body, which follows on the next line.
    public static func putScriptHeader(name: String, script: String) -> String {
        let byteCount = script.utf8.count
        return "PUTSCRIPT \(quote(name)) {\(byteCount)+}"
    }

    static func quote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

// MARK: - LISTSCRIPTS output

/// One entry from a `LISTSCRIPTS` response.
public struct ManageSieveScriptEntry: Sendable, Hashable {
    public let name: String
    public let isActive: Bool

    public init(name: String, isActive: Bool) {
        self.name = name
        self.isActive = isActive
    }

    /// Parses a `LISTSCRIPTS` data line: `"name"` or `"name" ACTIVE`. The name
    /// must be double-quoted — an unquoted line is not a script entry.
    public static func parse(_ line: String) -> ManageSieveScriptEntry? {
        guard line.contains("\""),
              let name = ManageSieveCapabilities.quotedTokens(in: line).first,
              !name.isEmpty
        else {
            return nil
        }
        let isActive = line.uppercased().contains("ACTIVE")
        return ManageSieveScriptEntry(name: name, isActive: isActive)
    }
}
