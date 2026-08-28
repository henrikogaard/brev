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

// MARK: - SRV record model

/// A single DNS SRV record (RFC 2782) for a mail service.
public struct MailServiceSRVRecord: Sendable, Hashable {
    public let priority: UInt16
    public let weight: UInt16
    public let port: UInt16
    /// The target hostname. A single "." means the service is explicitly not
    /// offered (RFC 2782) and the record must be ignored.
    public let target: String

    public init(priority: UInt16, weight: UInt16, port: UInt16, target: String) {
        self.priority = priority
        self.weight = weight
        self.port = port
        self.target = target
    }

    /// Whether this record advertises a usable target.
    var isUsable: Bool {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return !trimmed.isEmpty && port > 0
    }

    /// The target with any trailing FQDN dot removed.
    var normalizedTarget: String {
        var host = target.trimmingCharacters(in: .whitespacesAndNewlines)
        while host.hasSuffix(".") {
            host.removeLast()
        }
        return host.lowercased()
    }
}

/// The four RFC 6186 / RFC 8314 SRV lookups Brev performs for an email domain.
public struct MailServiceSRVRecordSet: Sendable, Hashable {
    /// `_imaps._tcp` — IMAP over implicit TLS.
    public var imaps: [MailServiceSRVRecord]
    /// `_imap._tcp` — IMAP with STARTTLS.
    public var imap: [MailServiceSRVRecord]
    /// `_submissions._tcp` — SMTP submission over implicit TLS (RFC 8314).
    public var submissions: [MailServiceSRVRecord]
    /// `_submission._tcp` — SMTP submission with STARTTLS.
    public var submission: [MailServiceSRVRecord]
    /// `_sieve._tcp` — ManageSieve (RFC 5804). STARTTLS only; there is no
    /// implicit-TLS SRV variant for ManageSieve.
    public var sieve: [MailServiceSRVRecord]

    public init(
        imaps: [MailServiceSRVRecord] = [],
        imap: [MailServiceSRVRecord] = [],
        submissions: [MailServiceSRVRecord] = [],
        submission: [MailServiceSRVRecord] = [],
        sieve: [MailServiceSRVRecord] = []
    ) {
        self.imaps = imaps
        self.imap = imap
        self.submissions = submissions
        self.submission = submission
        self.sieve = sieve
    }

    public var isEmpty: Bool {
        imaps.isEmpty && imap.isEmpty && submissions.isEmpty && submission.isEmpty && sieve.isEmpty
    }
}

// MARK: - RFC 6186 selection

/// Selects mail server settings from a set of SRV records per RFC 6186.
public enum MailSRVDiscovery {
    /// Builds a discovery result from `records`, preferring implicit TLS over
    /// STARTTLS for both IMAP and SMTP. Returns `nil` when neither a usable
    /// incoming nor outgoing record exists.
    public static func result(
        from records: MailServiceSRVRecordSet,
        domain: String
    ) -> MailAccountDiscoveryResult? {
        let incoming = incomingSettings(from: records)
        let outgoing = outgoingSettings(from: records)
        // ManageSieve is supplementary: it rides along on a result anchored by a
        // real incoming/outgoing endpoint and never synthesises one on its own.
        guard incoming != nil || outgoing != nil else { return nil }
        return MailAccountDiscoveryResult(
            domain: domain.lowercased(),
            displayName: nil,
            source: .dnsSRV,
            sourceURL: nil,
            incoming: incoming,
            outgoing: outgoing,
            manageSieve: manageSieveSettings(from: records),
            // SRV settings still require the user to enter credentials and
            // confirm, but the endpoints themselves are authoritative.
            requiresManualReview: incoming == nil || outgoing == nil
        )
    }

    /// ManageSieve (RFC 5804) settings from a `_sieve._tcp` record, or `nil`.
    /// ManageSieve has only a STARTTLS form; its endpoint is explicitly marked
    /// `.manageSieve` so it cannot be mistaken for an IMAP server.
    static func manageSieveSettings(from records: MailServiceSRVRecordSet) -> MailServerSettings? {
        guard let best = bestRecord(records.sieve) else { return nil }
        return MailServerSettings(
            kind: .manageSieve, host: best.normalizedTarget, port: best.port, tlsMode: .startTLS
        )
    }

    static func incomingSettings(from records: MailServiceSRVRecordSet) -> MailServerSettings? {
        if let best = bestRecord(records.imaps) {
            return MailServerSettings(
                kind: .imap, host: best.normalizedTarget, port: best.port, tlsMode: .implicit
            )
        }
        if let best = bestRecord(records.imap) {
            return MailServerSettings(
                kind: .imap, host: best.normalizedTarget, port: best.port, tlsMode: .startTLS
            )
        }
        return nil
    }

    static func outgoingSettings(from records: MailServiceSRVRecordSet) -> MailServerSettings? {
        if let best = bestRecord(records.submissions) {
            return MailServerSettings(
                kind: .smtp, host: best.normalizedTarget, port: best.port, tlsMode: .implicit
            )
        }
        if let best = bestRecord(records.submission) {
            return MailServerSettings(
                kind: .smtp, host: best.normalizedTarget, port: best.port, tlsMode: .startTLS
            )
        }
        return nil
    }

    /// Picks the preferred record: lowest priority wins; ties broken by highest
    /// weight (a coarse, deterministic stand-in for RFC 2782 weighted random
    /// selection — adequate for one-shot setup discovery).
    static func bestRecord(_ records: [MailServiceSRVRecord]) -> MailServiceSRVRecord? {
        records
            .filter(\.isUsable)
            .min { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
                return lhs.weight > rhs.weight
            }
    }
}

// MARK: - SRV rdata wire-format parsing

/// Parses the raw rdata bytes of a DNS SRV record (RFC 2782 wire format).
///
/// Isolated from the `dnssd` plumbing so the byte-level logic — big-endian
/// priority/weight/port followed by a DNS-encoded target name — is unit-tested
/// directly. Compression pointers are not expected in `dnssd`-expanded rdata
/// and are treated as a parse failure rather than followed.
public enum MailSRVRDataParser {
    public static func parse(_ rdata: Data) -> MailServiceSRVRecord? {
        let bytes = [UInt8](rdata)
        // 6 fixed bytes + at least the root label (1 byte).
        guard bytes.count >= 7 else { return nil }
        let priority = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        let weight = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
        let port = UInt16(bytes[4]) << 8 | UInt16(bytes[5])
        guard let target = decodeName(bytes, from: 6) else { return nil }
        return MailServiceSRVRecord(
            priority: priority, weight: weight, port: port, target: target
        )
    }

    /// Decodes a sequence of length-prefixed DNS labels starting at `offset`
    /// into a dotted hostname. Returns `nil` if a compression pointer or a
    /// label running past the buffer is encountered.
    static func decodeName(_ bytes: [UInt8], from offset: Int) -> String? {
        var index = offset
        var labels: [String] = []
        while index < bytes.count {
            let length = Int(bytes[index])
            if length == 0 {
                // Root label terminates the name. "." (empty labels) is valid
                // and means "service not offered" — return "." for the caller.
                return labels.isEmpty ? "." : labels.joined(separator: ".")
            }
            if length & 0xC0 != 0 { return nil } // compression pointer — unsupported
            let start = index + 1
            let end = start + length
            guard end <= bytes.count else { return nil }
            let label = String(decoding: bytes[start ..< end], as: UTF8.self)
            labels.append(label)
            index = end
        }
        return nil
    }
}
