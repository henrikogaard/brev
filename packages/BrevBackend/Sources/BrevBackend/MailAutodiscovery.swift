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

import dnssd
import Foundation

// MARK: - Probe protocol

/// Performs the two network probes the autodiscovery orchestrator needs.
///
/// Injected so the profile → SRV → autoconfig → manual ordering can be tested
/// without touching the network (`MailAccountAutodiscovery.discover`). The live
/// implementation is `LiveMailAutodiscoveryProbe`.
public protocol MailAutodiscoveryProbing: Sendable {
    /// Resolves the RFC 6186 / RFC 8314 SRV records for `domain`. Uses only the
    /// domain — never the full email address. Returns an empty set on failure.
    func srvRecords(forDomain domain: String) async -> MailServiceSRVRecordSet

    /// Fetches the provider-local Thunderbird autoconfig XML for `emailAddress`.
    /// May transmit the full email address to provider-local hosts (disclosed in
    /// the setup UI per ADR-0028). Returns `nil` on failure.
    func autoconfigXML(forEmailAddress emailAddress: String, domain: String) async -> (data: Data, url: URL)?

    /// Resolves the DNS MX records for `domain`. Uses only the domain — never
    /// the full email address. Returns an empty array on failure.
    func mxRecords(forDomain domain: String) async -> [MailMXRecord]
}

public extension MailAutodiscoveryProbing {
    /// Default: no MX records. Lets probes that predate MX discovery (and test
    /// stubs that don't exercise it) conform without change.
    func mxRecords(forDomain domain: String) async -> [MailMXRecord] { [] }
}

// MARK: - Orchestrator

public extension MailAccountAutodiscovery {
    /// Resolves IMAP/SMTP settings for `emailAddress` following the ADR-0028
    /// order: built-in profile → DNS SRV → provider autoconfig → manual
    /// fallback. The first method that yields settings wins. Network probes are
    /// injected via `probe`; the default performs real DNS/HTTPS lookups.
    ///
    /// Always returns a result — `manualFallback` is the floor — so callers can
    /// present a populated form even with no connectivity.
    static func discover(
        forEmailAddress emailAddress: String,
        using probe: any MailAutodiscoveryProbing = LiveMailAutodiscoveryProbe()
    ) async -> MailAccountDiscoveryResult {
        // 1. Built-in provider profile (offline, most trusted).
        if let profileResult = profile(forEmailAddress: emailAddress) {
            return profileResult
        }

        let domain = discoveryDomain(from: emailAddress)
        // Defence in depth: only probe the network for a clean FQDN. A domain
        // carrying URL-significant characters (an embedded "@", "/", ":") could
        // otherwise relocate the autoconfig probe — and the user's email — to an
        // attacker-controlled authority (e.g. `you@corp.com@evil.com`). The setup
        // UI already gates on `isValidEmailAddress`, but this is the public
        // entrypoint, so it must not rely on the caller having validated.
        guard !domain.isEmpty, MailAccountAutodiscovery.isValidServerHost(domain) else {
            return manualFallback(forEmailAddress: emailAddress)
        }

        // 2. DNS SRV (RFC 6186) — domain only, no email address transmitted.
        let srv = await probe.srvRecords(forDomain: domain)
        if !srv.isEmpty, let srvResult = MailSRVDiscovery.result(from: srv, domain: domain) {
            return srvResult
        }

        // 3. Provider-local Thunderbird autoconfig over HTTPS.
        if let fetched = await probe.autoconfigXML(forEmailAddress: emailAddress, domain: domain),
           let autoconfigResult = MozillaAutoconfigParser.parse(
               xml: fetched.data, domain: domain, sourceURL: fetched.url
           ) {
            return autoconfigResult
        }

        // 4. DNS MX → known provider. Catches custom domains that delegate mail
        // to a provider Brev knows (the common case where SRV/autoconfig are
        // both absent) instead of falling straight to a `imap.<domain>` guess.
        let mx = await probe.mxRecords(forDomain: domain)
        if let mxResult = providerResult(forMXRecords: mx, emailAddress: emailAddress) {
            return mxResult
        }

        // 5. Conservative manual-entry defaults.
        return manualFallback(forEmailAddress: emailAddress)
    }

    /// Lower-cased domain portion of `emailAddress`, or "" when malformed.
    static func discoveryDomain(from emailAddress: String) -> String {
        let trimmed = emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "@", maxSplits: 1)
        return parts.count == 2 ? String(parts[1]).lowercased() : ""
    }
}

// MARK: - Live probe

/// The production `MailAutodiscoveryProbing` implementation: `dnssd` SRV lookups
/// and provider-local HTTPS autoconfig fetches.
public struct LiveMailAutodiscoveryProbe: MailAutodiscoveryProbing {
    private let queryTimeout: TimeInterval

    public init(queryTimeout: TimeInterval = 4) {
        self.queryTimeout = queryTimeout
    }

    // MARK: SRV

    public func srvRecords(forDomain domain: String) async -> MailServiceSRVRecordSet {
        async let imaps = Self.querySRV("_imaps._tcp.\(domain)", timeout: queryTimeout)
        async let imap = Self.querySRV("_imap._tcp.\(domain)", timeout: queryTimeout)
        async let submissions = Self.querySRV("_submissions._tcp.\(domain)", timeout: queryTimeout)
        async let submission = Self.querySRV("_submission._tcp.\(domain)", timeout: queryTimeout)
        async let sieve = Self.querySRV("_sieve._tcp.\(domain)", timeout: queryTimeout)
        return await MailServiceSRVRecordSet(
            imaps: imaps, imap: imap, submissions: submissions, submission: submission, sieve: sieve
        )
    }

    // MARK: MX

    public func mxRecords(forDomain domain: String) async -> [MailMXRecord] {
        await Self.queryMX(domain, timeout: queryTimeout)
    }

    /// Resolves SRV records for `fullName` via `dnssd`. The rdata byte parsing is
    /// delegated to the unit-tested `MailSRVRDataParser`; the query plumbing and
    /// `poll`-based timeout are shared with `queryMX`.
    static func querySRV(_ fullName: String, timeout: TimeInterval) async -> [MailServiceSRVRecord] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[MailServiceSRVRecord], Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let rdata = blockingQuery(fullName, type: UInt16(kDNSServiceType_SRV), timeout: timeout)
                continuation.resume(returning: rdata.compactMap(MailSRVRDataParser.parse))
            }
        }
    }

    /// Resolves MX records for `domain` via `dnssd`, parsing each rdata blob with
    /// the unit-tested `MailMXRDataParser`.
    static func queryMX(_ domain: String, timeout: TimeInterval) async -> [MailMXRecord] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[MailMXRecord], Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let rdata = blockingQuery(domain, type: UInt16(kDNSServiceType_MX), timeout: timeout)
                continuation.resume(returning: rdata.compactMap(MailMXRDataParser.parse))
            }
        }
    }

    /// Performs a blocking `dnssd` query for `fullName`/`type` and returns the
    /// raw rdata of each answer. Record-type agnostic so SRV and MX share it.
    private static func blockingQuery(_ fullName: String, type: UInt16, timeout: TimeInterval) -> [Data] {
        let collector = DNSRDataCollector()
        let context = Unmanaged.passRetained(collector).toOpaque()
        var sdRef: DNSServiceRef?
        let status = DNSServiceQueryRecord(
            &sdRef,
            0,
            0,
            fullName,
            type,
            UInt16(kDNSServiceClass_IN),
            dnsRDataCallback,
            context
        )
        guard status == kDNSServiceErr_NoError, let ref = sdRef else {
            Unmanaged<DNSRDataCollector>.fromOpaque(context).release()
            return []
        }
        defer {
            DNSServiceRefDeallocate(ref)
            Unmanaged<DNSRDataCollector>.fromOpaque(context).release()
        }
        let fd = DNSServiceRefSockFD(ref)
        guard fd >= 0 else { return [] }
        let deadline = Date().addingTimeInterval(timeout)
        while !collector.done, Date() < deadline {
            let remainingMs = max(0, Int32(deadline.timeIntervalSinceNow * 1000))
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pfd, 1, remainingMs)
            if ready <= 0 { break } // timeout or error
            if DNSServiceProcessResult(ref) != kDNSServiceErr_NoError { break }
        }
        return collector.rdata
    }

    // MARK: Autoconfig

    public func autoconfigXML(
        forEmailAddress emailAddress: String,
        domain: String
    ) async -> (data: Data, url: URL)? {
        // Defence in depth: never probe a domain that isn't a clean FQDN. An
        // embedded "@" in `domain` would otherwise turn `autoconfig.<domain>`
        // into userinfo and move the request (and the user's email) to an
        // attacker-controlled host. The orchestrator validates too, but this is
        // a public protocol method callable directly.
        guard MailAccountAutodiscovery.isValidServerHost(domain) else { return nil }
        // Provider-local endpoints only (Thunderbird "ISPDB" third-party host is
        // intentionally excluded — ADR-0028 specifies provider-local autoconfig).
        let candidates: [(host: String, path: String)] = [
            ("autoconfig.\(domain)", "/mail/config-v1.1.xml"),
            (domain, "/.well-known/autoconfig/mail/config-v1.1.xml"),
        ]
        for candidate in candidates {
            // Build the URL with an explicit host rather than string
            // interpolation, then assert the authority is exactly the host we
            // intended. `URLComponents` percent-encodes the email in the query,
            // so a stray character cannot escape into the authority.
            var components = URLComponents()
            components.scheme = "https"
            components.host = candidate.host
            components.path = candidate.path
            components.queryItems = [URLQueryItem(name: "emailaddress", value: emailAddress)]
            guard let url = components.url, url.host == candidate.host else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = queryTimeout
            request.setValue("text/xml, application/xml", forHTTPHeaderField: "Accept")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse,
                  (200 ..< 300).contains(http.statusCode),
                  !data.isEmpty
            else {
                continue
            }
            return (data, url)
        }
        return nil
    }
}

// MARK: - dnssd callback plumbing

/// Accumulates the raw rdata blobs delivered by `DNSServiceQueryRecord`
/// callbacks. Record-type agnostic; parsing happens after the query completes.
private final class DNSRDataCollector {
    var rdata: [Data] = []
    var done = false
}

/// C callback for `DNSServiceQueryRecord`. Non-capturing so it bridges to a C
/// function pointer; the collector arrives via the opaque `context`. It only
/// copies rdata bytes — record parsing is left to the caller's typed parser.
private func dnsRDataCallback(
    sdRef: DNSServiceRef?,
    flags: DNSServiceFlags,
    interfaceIndex: UInt32,
    errorCode: DNSServiceErrorType,
    fullname: UnsafePointer<CChar>?,
    rrtype: UInt16,
    rrclass: UInt16,
    rdlen: UInt16,
    rdata: UnsafeRawPointer?,
    ttl: UInt32,
    context: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    let collector = Unmanaged<DNSRDataCollector>.fromOpaque(context).takeUnretainedValue()
    if errorCode == kDNSServiceErr_NoError, let rdata, rdlen > 0 {
        collector.rdata.append(Data(bytes: rdata, count: Int(rdlen)))
    }
    if flags & DNSServiceFlags(kDNSServiceFlagsMoreComing) == 0 {
        collector.done = true
    }
}
