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

// MARK: - MX record model

/// A single DNS MX record (RFC 1035): the mail exchanger host and its
/// preference (lower is more preferred).
public struct MailMXRecord: Sendable, Hashable {
    public let preference: UInt16
    /// The exchanger hostname, lowercased with any trailing FQDN dot removed.
    public let exchange: String

    public init(preference: UInt16, exchange: String) {
        self.preference = preference
        var host = exchange.trimmingCharacters(in: .whitespacesAndNewlines)
        while host.hasSuffix(".") {
            host.removeLast()
        }
        self.exchange = host.lowercased()
    }

    /// Whether this record advertises a usable exchanger. A single "." means
    /// "no mail service" (RFC 7505 null MX) and is not usable.
    var isUsable: Bool { !exchange.isEmpty }
}

// MARK: - MX rdata wire-format parsing

/// Parses the raw rdata bytes of a DNS MX record (RFC 1035 wire format):
/// a big-endian 2-byte preference followed by a DNS-encoded exchanger name.
///
/// The name decoding is shared with `MailSRVRDataParser` so compression
/// pointers (not expected in `dnssd`-expanded rdata) are treated as a parse
/// failure rather than followed.
public enum MailMXRDataParser {
    public static func parse(_ rdata: Data) -> MailMXRecord? {
        let bytes = [UInt8](rdata)
        // 2 fixed bytes + at least the root label (1 byte).
        guard bytes.count >= 3 else { return nil }
        let preference = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        guard let name = MailSRVRDataParser.decodeName(bytes, from: 2) else { return nil }
        // "." is the RFC 7505 null MX — surface it as an empty (unusable) host.
        return MailMXRecord(preference: preference, exchange: name == "." ? "" : name)
    }
}

// MARK: - MX → provider mapping

/// Maps a domain's MX exchangers to a built-in provider profile.
///
/// Most custom domains never publish IMAP/SMTP SRV records or a usable
/// Thunderbird autoconfig endpoint, but they almost always delegate mail to a
/// known provider via MX. Matching
/// the lowest-preference exchanger to a provider lets discovery resolve the
/// real servers instead of guessing `imap.<domain>` / `smtp.<domain>`.
public enum MailMXProviderResolver {
    /// `(hostSuffix, providerEmailDomain)` pairs. The provider domain is fed
    /// back into `MailAccountAutodiscovery.matchBuiltInProfile(for:)`, so each
    /// must match a `case` there. Order is irrelevant — matching is by suffix.
    static let providerSuffixes: [(suffix: String, providerDomain: String)] = [
        ("google.com", "gmail.com"),
        ("googlemail.com", "gmail.com"),
        ("protection.outlook.com", "outlook.com"),
        ("outlook.com", "outlook.com"),
        ("office365.com", "outlook.com"),
        ("messagingengine.com", "fastmail.com"),
        ("fastmail.com", "fastmail.com"),
        ("mailbox.org", "mailbox.org"),
        ("posteo.de", "posteo.de"),
        ("zoho.com", "zoho.com"),
        ("zoho.eu", "zoho.com"),
        ("zohomail.com", "zoho.com"),
        ("protonmail.ch", "proton.me"),
        ("proton.me", "proton.me"),
        ("gmx.net", "gmx.com"),
        ("gmx.com", "gmx.com"),
        ("runbox.com", "runbox.com"),
        ("icloud.com", "icloud.com"),
        ("me.com", "icloud.com"),
        ("yahoodns.net", "yahoo.com"),
        ("yahoo.com", "yahoo.com"),
    ]

    /// Returns the canonical provider email domain for `records` — the provider
    /// the most-preferred usable exchanger belongs to — or `nil` when no
    /// exchanger matches a known provider.
    public static func providerDomain(for records: [MailMXRecord]) -> String? {
        let ordered = records.filter(\.isUsable).sorted { $0.preference < $1.preference }
        for record in ordered {
            if let providerDomain = providerDomain(forExchange: record.exchange) {
                return providerDomain
            }
        }
        return nil
    }

    /// Matches a single exchanger hostname to a provider domain by suffix.
    static func providerDomain(forExchange exchange: String) -> String? {
        let host = exchange.lowercased()
        for entry in providerSuffixes where host == entry.suffix || host.hasSuffix("." + entry.suffix) {
            return entry.providerDomain
        }
        return nil
    }
}
