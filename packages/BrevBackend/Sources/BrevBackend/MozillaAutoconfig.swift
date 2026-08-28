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

// MARK: - Thunderbird/Mozilla autoconfig parsing

/// Parses Thunderbird/Mozilla "autoconfig" `clientConfig` XML (config-v1.1)
/// into a `MailAccountDiscoveryResult`.
///
/// This is pure (no network): the caller fetches the XML from a provider-local
/// autoconfig endpoint and passes the bytes here. Per ADR-0028 only the first
/// IMAP `incomingServer` and the first SMTP `outgoingServer` are used; insecure
/// (`plain` socket) servers are rejected so discovery never downgrades TLS.
public enum MozillaAutoconfigParser {
    /// Parses `xml` and returns resolved IMAP/SMTP settings, or `nil` if the
    /// document has no usable secure IMAP + SMTP pair.
    public static func parse(
        xml: Data,
        domain: String,
        sourceURL: URL? = nil
    ) -> MailAccountDiscoveryResult? {
        let delegate = AutoconfigXMLDelegate()
        let parser = XMLParser(data: xml)
        parser.delegate = delegate
        guard parser.parse() else { return nil }

        guard let imap = delegate.server(kind: .imap),
              let smtp = delegate.server(kind: .smtp),
              let incoming = imap.asServerSettings(kind: .imap),
              let outgoing = smtp.asServerSettings(kind: .smtp)
        else {
            return nil
        }

        return MailAccountDiscoveryResult(
            domain: domain.lowercased(),
            displayName: delegate.displayName,
            source: .providerAutoconfig,
            sourceURL: sourceURL,
            incoming: incoming,
            outgoing: outgoing,
            requiresManualReview: false
        )
    }
}

// MARK: - Parsed server intermediate

/// A single `<incomingServer>` / `<outgoingServer>` block collected from the XML.
struct AutoconfigParsedServer {
    var typeAttribute: String?
    var hostname: String?
    var port: UInt16?
    var socketType: String?
    var authentication: String?
    var username: String?

    /// Maps the parsed fields to `MailServerSettings`, returning `nil` when a
    /// secure host/port/socket can't be resolved.
    func asServerSettings(kind: MailServerProtocolKind) -> MailServerSettings? {
        guard let host = hostname?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty
        else {
            return nil
        }
        guard let tls = Self.tlsMode(from: socketType) else { return nil }
        let resolvedPort = port ?? Self.defaultPort(kind: kind, tls: tls)
        return MailServerSettings(
            kind: kind,
            host: host,
            port: resolvedPort,
            tlsMode: tls,
            authentication: Self.authentication(from: authentication),
            usernameTemplate: Self.usernameTemplate(from: username)
        )
    }

    /// Maps a Thunderbird `socketType` to a Brev TLS mode. `plain` (no TLS) is
    /// rejected — Brev never auto-configures an unencrypted mail connection.
    static func tlsMode(from socketType: String?) -> MailServerTLSMode? {
        switch socketType?.uppercased() {
        case "SSL", "TLS": return .implicit
        case "STARTTLS": return .startTLS
        default: return nil
        }
    }

    static func defaultPort(kind: MailServerProtocolKind, tls: MailServerTLSMode) -> UInt16 {
        switch (kind, tls) {
        case (.imap, .implicit): return 993
        case (.imap, .startTLS): return 143
        case (.smtp, .implicit): return 465
        case (.smtp, .startTLS): return 587
        case (.manageSieve, _): return 4190
        }
    }

    /// Maps Thunderbird `authentication` values to a Brev mechanism. Unknown or
    /// `password-encrypted` (CRAM-MD5 etc., unsupported) values fall back to a
    /// plain password, which the user can correct in the setup form.
    static func authentication(from value: String?) -> MailServerAuthentication {
        switch value?.lowercased() {
        case "oauth2": return .xoauth2
        case "none": return .none
        default: return .password
        }
    }

    static func usernameTemplate(from value: String?) -> String {
        guard let value, !value.isEmpty else { return "%EMAILADDRESS%" }
        // Thunderbird uses %EMAILADDRESS% and %EMAILLOCALPART%; normalize the
        // local-part token to Brev's %LOCALPART%.
        return value.replacingOccurrences(of: "%EMAILLOCALPART%", with: "%LOCALPART%")
    }
}

// MARK: - XMLParser delegate

/// Collects the first IMAP `incomingServer` and first SMTP `outgoingServer`
/// from a Thunderbird `clientConfig` document.
private final class AutoconfigXMLDelegate: NSObject, XMLParserDelegate {
    private(set) var displayName: String?
    private var servers: [AutoconfigParsedServer] = []

    private var current: AutoconfigParsedServer?
    private var currentElement: String?
    private var textBuffer = ""

    /// Returns the first parsed server whose `type` attribute matches `kind`.
    func server(kind: MailServerProtocolKind) -> AutoconfigParsedServer? {
        servers.first { ($0.typeAttribute?.lowercased() == kind.rawValue) }
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        let name = elementName.lowercased()
        textBuffer = ""
        currentElement = name
        if name == "incomingserver" || name == "outgoingserver" {
            var server = AutoconfigParsedServer()
            server.typeAttribute = attributeDict["type"]
            current = server
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.lowercased()
        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { textBuffer = "" }

        if name == "incomingserver" || name == "outgoingserver" {
            if let server = current { servers.append(server) }
            current = nil
            return
        }

        if current != nil {
            switch name {
            case "hostname": current?.hostname = text
            case "port": current?.port = UInt16(text)
            case "sockettype": current?.socketType = text
            case "authentication":
                // First non-empty authentication wins; later ones are alternatives.
                if current?.authentication == nil, !text.isEmpty {
                    current?.authentication = text
                }
            case "username": current?.username = text
            default: break
            }
        } else if name == "displayname", displayName == nil, !text.isEmpty {
            displayName = text
        }
    }
}
