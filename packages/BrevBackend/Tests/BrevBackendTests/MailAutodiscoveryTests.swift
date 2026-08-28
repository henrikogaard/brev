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

@testable import BrevBackend
import Foundation
import Testing

// MARK: - Mozilla autoconfig parsing

@Suite("MozillaAutoconfigParser")
struct MozillaAutoconfigParserTests {
    private static let validXML = """
    <?xml version="1.0"?>
    <clientConfig version="1.1">
      <emailProvider id="example.com">
        <domain>example.com</domain>
        <displayName>Example Mail</displayName>
        <incomingServer type="imap">
          <hostname>imap.example.com</hostname>
          <port>993</port>
          <socketType>SSL</socketType>
          <authentication>password-cleartext</authentication>
          <username>%EMAILADDRESS%</username>
        </incomingServer>
        <outgoingServer type="smtp">
          <hostname>smtp.example.com</hostname>
          <port>587</port>
          <socketType>STARTTLS</socketType>
          <authentication>password-cleartext</authentication>
          <username>%EMAILLOCALPART%</username>
        </outgoingServer>
      </emailProvider>
    </clientConfig>
    """

    @Test("parses incoming + outgoing servers, TLS modes, and display name")
    func parsesValidConfig() throws {
        let result = try #require(
            MozillaAutoconfigParser.parse(xml: Data(Self.validXML.utf8), domain: "example.com")
        )
        #expect(result.source == .providerAutoconfig)
        #expect(result.displayName == "Example Mail")
        #expect(result.incoming?.host == "imap.example.com")
        #expect(result.incoming?.port == 993)
        #expect(result.incoming?.tlsMode == .implicit)
        #expect(result.outgoing?.host == "smtp.example.com")
        #expect(result.outgoing?.port == 587)
        #expect(result.outgoing?.tlsMode == .startTLS)
        // %EMAILLOCALPART% is normalized to Brev's %LOCALPART% token.
        #expect(result.outgoing?.usernameTemplate == "%LOCALPART%")
    }

    @Test("rejects a config whose only servers use an insecure plain socket")
    func rejectsPlainSocket() {
        let xml = """
        <clientConfig><emailProvider>
          <incomingServer type="imap"><hostname>imap.x.com</hostname><port>143</port>
            <socketType>plain</socketType></incomingServer>
          <outgoingServer type="smtp"><hostname>smtp.x.com</hostname><port>25</port>
            <socketType>plain</socketType></outgoingServer>
        </emailProvider></clientConfig>
        """
        #expect(MozillaAutoconfigParser.parse(xml: Data(xml.utf8), domain: "x.com") == nil)
    }

    @Test("returns nil when an outgoing server is absent")
    func requiresBothServers() {
        let xml = """
        <clientConfig><emailProvider>
          <incomingServer type="imap"><hostname>imap.x.com</hostname><port>993</port>
            <socketType>SSL</socketType></incomingServer>
        </emailProvider></clientConfig>
        """
        #expect(MozillaAutoconfigParser.parse(xml: Data(xml.utf8), domain: "x.com") == nil)
    }
}

// MARK: - SRV rdata parsing

@Suite("MailSRVRDataParser")
struct MailSRVRDataParserTests {
    /// Builds SRV rdata: priority, weight, port (big-endian), then a
    /// DNS-encoded target name.
    private static func rdata(priority: UInt16, weight: UInt16, port: UInt16, labels: [String]) -> Data {
        var bytes: [UInt8] = [
            UInt8(priority >> 8), UInt8(priority & 0xFF),
            UInt8(weight >> 8), UInt8(weight & 0xFF),
            UInt8(port >> 8), UInt8(port & 0xFF),
        ]
        for label in labels {
            bytes.append(UInt8(label.utf8.count))
            bytes.append(contentsOf: Array(label.utf8))
        }
        bytes.append(0) // root label
        return Data(bytes)
    }

    @Test("decodes priority, weight, port, and a multi-label target")
    func parsesRecord() throws {
        let data = Self.rdata(priority: 10, weight: 5, port: 993, labels: ["imap", "example", "com"])
        let record = try #require(MailSRVRDataParser.parse(data))
        #expect(record.priority == 10)
        #expect(record.weight == 5)
        #expect(record.port == 993)
        #expect(record.target == "imap.example.com")
        #expect(record.isUsable)
    }

    @Test("a root-only target means the service is not offered")
    func rootTargetNotOffered() throws {
        let data = Self.rdata(priority: 0, weight: 0, port: 0, labels: [])
        let record = try #require(MailSRVRDataParser.parse(data))
        #expect(record.target == ".")
        #expect(!record.isUsable)
    }

    @Test("rejects truncated rdata")
    func rejectsTruncated() {
        #expect(MailSRVRDataParser.parse(Data([0x00, 0x0A, 0x00])) == nil)
    }
}

// MARK: - RFC 6186 selection

@Suite("MailSRVDiscovery")
struct MailSRVDiscoveryTests {
    @Test("prefers implicit-TLS imaps over STARTTLS imap, lowest priority wins")
    func selectsPreferredRecords() throws {
        let records = MailServiceSRVRecordSet(
            imaps: [
                MailServiceSRVRecord(priority: 20, weight: 1, port: 993, target: "imap-b.x.com"),
                MailServiceSRVRecord(priority: 10, weight: 1, port: 993, target: "imap-a.x.com"),
            ],
            imap: [MailServiceSRVRecord(priority: 1, weight: 1, port: 143, target: "old.x.com")],
            submissions: [MailServiceSRVRecord(priority: 5, weight: 1, port: 465, target: "smtp.x.com")]
        )
        let result = try #require(MailSRVDiscovery.result(from: records, domain: "x.com"))
        #expect(result.source == .dnsSRV)
        // imaps preferred over imap even though imap has a lower priority number.
        #expect(result.incoming?.host == "imap-a.x.com")
        #expect(result.incoming?.tlsMode == .implicit)
        #expect(result.outgoing?.host == "smtp.x.com")
        #expect(result.outgoing?.tlsMode == .implicit)
    }

    @Test("falls back to STARTTLS submission when no implicit submissions exist")
    func startTLSSubmissionFallback() throws {
        let records = MailServiceSRVRecordSet(
            imaps: [MailServiceSRVRecord(priority: 1, weight: 1, port: 993, target: "imap.x.com")],
            submission: [MailServiceSRVRecord(priority: 1, weight: 1, port: 587, target: "smtp.x.com")]
        )
        let result = try #require(MailSRVDiscovery.result(from: records, domain: "x.com"))
        #expect(result.outgoing?.tlsMode == .startTLS)
        #expect(result.outgoing?.port == 587)
    }

    @Test("ignores not-offered (\".\") records")
    func ignoresNotOffered() {
        let records = MailServiceSRVRecordSet(
            imaps: [MailServiceSRVRecord(priority: 0, weight: 0, port: 0, target: ".")]
        )
        #expect(MailSRVDiscovery.result(from: records, domain: "x.com") == nil)
    }

    @Test("discovers ManageSieve from a _sieve._tcp record (STARTTLS on the advertised port)")
    func discoversManageSieve() throws {
        let records = MailServiceSRVRecordSet(
            imaps: [MailServiceSRVRecord(priority: 1, weight: 1, port: 993, target: "imap.x.com")],
            submissions: [MailServiceSRVRecord(priority: 1, weight: 1, port: 465, target: "smtp.x.com")],
            sieve: [
                MailServiceSRVRecord(priority: 20, weight: 1, port: 4190, target: "sieve-b.x.com"),
                MailServiceSRVRecord(priority: 10, weight: 1, port: 4190, target: "sieve-a.x.com"),
            ]
        )
        let result = try #require(MailSRVDiscovery.result(from: records, domain: "x.com"))
        // ManageSieve has no implicit-TLS SRV variant; RFC 5804 is STARTTLS on 4190.
        #expect(result.manageSieve?.host == "sieve-a.x.com")
        #expect(result.manageSieve?.port == 4190)
        #expect(result.manageSieve?.kind == .manageSieve)
        #expect(result.manageSieve?.tlsMode == .startTLS)
    }

    @Test("a sieve record alone does not synthesise an account result")
    func sieveAloneIsNotAResult() {
        let records = MailServiceSRVRecordSet(
            sieve: [MailServiceSRVRecord(priority: 1, weight: 1, port: 4190, target: "sieve.x.com")]
        )
        #expect(MailSRVDiscovery.result(from: records, domain: "x.com") == nil)
    }

    @Test("no sieve record leaves ManageSieve unset")
    func noManageSieveWhenAbsent() throws {
        let records = MailServiceSRVRecordSet(
            imaps: [MailServiceSRVRecord(priority: 1, weight: 1, port: 993, target: "imap.x.com")]
        )
        let result = try #require(MailSRVDiscovery.result(from: records, domain: "x.com"))
        #expect(result.manageSieve == nil)
    }
}

// MARK: - Orchestration

private struct StubProbe: MailAutodiscoveryProbing {
    var srv = MailServiceSRVRecordSet()
    var autoconfig: (data: Data, url: URL)?
    var mx: [MailMXRecord] = []

    func srvRecords(forDomain domain: String) async -> MailServiceSRVRecordSet { srv }
    func autoconfigXML(forEmailAddress emailAddress: String, domain: String) async -> (data: Data, url: URL)? {
        autoconfig
    }

    func mxRecords(forDomain domain: String) async -> [MailMXRecord] { mx }
}

@Suite("MailAccountAutodiscovery.discover")
struct MailAutodiscoveryOrchestrationTests {
    @Test("a built-in profile short-circuits before any network probe")
    func builtInProfileWins() async {
        let result = await MailAccountAutodiscovery.discover(
            forEmailAddress: "user@fastmail.com",
            using: StubProbe(srv: MailServiceSRVRecordSet()) // would be empty anyway
        )
        #expect(result.source == .builtInProfile)
        #expect(result.displayName == "Fastmail")
    }

    @Test("DNS SRV is used for an unknown domain before autoconfig")
    func srvBeforeAutoconfig() async {
        let probe = StubProbe(
            srv: MailServiceSRVRecordSet(
                imaps: [MailServiceSRVRecord(priority: 1, weight: 1, port: 993, target: "imap.acme.test")],
                submissions: [MailServiceSRVRecord(priority: 1, weight: 1, port: 465, target: "smtp.acme.test")]
            )
        )
        let result = await MailAccountAutodiscovery.discover(forEmailAddress: "user@acme.test", using: probe)
        #expect(result.source == .dnsSRV)
        #expect(result.incoming?.host == "imap.acme.test")
    }

    @Test("autoconfig is used when SRV is empty")
    func autoconfigFallback() async {
        let xml = Data("""
        <clientConfig><emailProvider><displayName>Acme</displayName>
          <incomingServer type="imap"><hostname>imap.acme.test</hostname><port>993</port>
            <socketType>SSL</socketType></incomingServer>
          <outgoingServer type="smtp"><hostname>smtp.acme.test</hostname><port>465</port>
            <socketType>SSL</socketType></outgoingServer>
        </emailProvider></clientConfig>
        """.utf8)
        let probe = StubProbe(autoconfig: (xml, URL(string: "https://autoconfig.acme.test")!))
        let result = await MailAccountAutodiscovery.discover(forEmailAddress: "user@acme.test", using: probe)
        #expect(result.source == .providerAutoconfig)
        #expect(result.displayName == "Acme")
    }

    @Test("manual fallback is the floor when nothing resolves")
    func manualFallbackFloor() async {
        let result = await MailAccountAutodiscovery.discover(
            forEmailAddress: "user@acme.test",
            using: StubProbe()
        )
        #expect(result.source == .manualFallback)
        #expect(result.incoming?.host == "imap.acme.test")
        #expect(result.requiresManualReview)
    }

    @Test("DNS MX maps a custom domain to its provider when SRV/autoconfig are absent")
    func mxProviderMatch() async {
        let probe = StubProbe(
            mx: [MailMXRecord(preference: 5, exchange: "in1-smtp.messagingengine.com.")]
        )
        let result = await MailAccountAutodiscovery.discover(forEmailAddress: "person@studio.example", using: probe)
        #expect(result.source == .dnsMXProvider)
        #expect(result.displayName == "Fastmail")
        #expect(result.incoming?.host == "imap.fastmail.com")
        // Re-keyed to the user's real domain, not the provider's.
        #expect(result.domain == "studio.example")
        #expect(result.requiresManualReview == false)
    }

    @Test("DNS MX is only consulted after autoconfig fails")
    func autoconfigWinsOverMX() async {
        let xml = Data("""
        <clientConfig><emailProvider><displayName>Acme</displayName>
          <incomingServer type="imap"><hostname>imap.acme.test</hostname><port>993</port>
            <socketType>SSL</socketType></incomingServer>
          <outgoingServer type="smtp"><hostname>smtp.acme.test</hostname><port>465</port>
            <socketType>SSL</socketType></outgoingServer>
        </emailProvider></clientConfig>
        """.utf8)
        let probe = StubProbe(
            autoconfig: (xml, URL(string: "https://autoconfig.acme.test")!),
            mx: [MailMXRecord(preference: 5, exchange: "in1-smtp.messagingengine.com")]
        )
        let result = await MailAccountAutodiscovery.discover(forEmailAddress: "user@acme.test", using: probe)
        #expect(result.source == .providerAutoconfig)
    }

    @Test("an unknown MX exchanger falls through to manual entry")
    func unknownMXFallsThrough() async {
        let probe = StubProbe(mx: [MailMXRecord(preference: 10, exchange: "mail.self-hosted.example")])
        let result = await MailAccountAutodiscovery.discover(forEmailAddress: "user@self-hosted.example", using: probe)
        #expect(result.source == .manualFallback)
    }

    @Test("an embedded-@ domain never reaches a network probe (credential-theft guard)")
    func embeddedAtDomainShortCircuitsBeforeProbe() async {
        // If the userinfo guard were missing, `you@corp.com@evil.com` would
        // resolve to domain "corp.com@evil.com", and `autoconfig.<domain>`
        // would put the user's email in the userinfo of the attacker host
        // `evil.com`. The stub returns a fully valid attacker config; the
        // orchestrator must ignore it and fall through to manual entry.
        let attackerXML = Data("""
        <clientConfig><emailProvider><displayName>Attacker</displayName>
          <incomingServer type="imap"><hostname>imap.evil.com</hostname><port>993</port>
            <socketType>SSL</socketType></incomingServer>
          <outgoingServer type="smtp"><hostname>smtp.evil.com</hostname><port>465</port>
            <socketType>SSL</socketType></outgoingServer>
        </emailProvider></clientConfig>
        """.utf8)
        let probe = StubProbe(autoconfig: (attackerXML, URL(string: "https://autoconfig.evil.com")!))
        let result = await MailAccountAutodiscovery.discover(
            forEmailAddress: "you@corp.com@evil.com",
            using: probe
        )
        #expect(result.source == .manualFallback)
        #expect(result.displayName != "Attacker")
    }
}

// MARK: - Hostname / email validation

@Suite("MailAccountAutodiscovery host validation")
struct MailAccountAutodiscoveryHostValidationTests {
    @Test("accepts clean multi-label FQDNs")
    func acceptsCleanHosts() {
        for host in ["example.com", "imap.example.com", "a-b.co", "mx1.sub.example.org", "xn--80ak6aa92e.com"] {
            #expect(MailAccountAutodiscovery.isValidServerHost(host), "expected \(host) to be valid")
        }
    }

    @Test("accepts a root-anchored FQDN with a single trailing dot")
    func acceptsTrailingDotFQDN() {
        // A trailing dot is a legitimate root anchor (canonicalized away before
        // storage). It must not be rejected; a doubled trailing dot still is.
        #expect(MailAccountAutodiscovery.isValidServerHost("imap.example.org."))
        #expect(MailAccountAutodiscovery.isValidServerHost(" IMAP.Example.ORG. "))
        #expect(!MailAccountAutodiscovery.isValidServerHost("imap.example.org.."))
    }

    @Test("rejects URL-significant characters that could relocate the authority")
    func rejectsURLSignificantCharacters() {
        for host in [
            "company.com@evil.com", // embedded userinfo
            "host/path.com",
            "host:993.com",
            "host?x=1.com",
            "host#frag.com",
            "evil.com\\@corp.com",
        ] {
            #expect(!MailAccountAutodiscovery.isValidServerHost(host), "expected \(host) to be rejected")
        }
    }

    @Test("rejects malformed label shapes")
    func rejectsMalformedLabels() {
        for host in ["", "host", ".com", "com.", "a..b", "_dmarc.example.com", "ho st.com", "-bad.com", "bad-.com"] {
            #expect(!MailAccountAutodiscovery.isValidServerHost(host), "expected \(host) to be rejected")
        }
    }

    @Test("isValidEmailAddress rejects a second @ that would forge the domain")
    func emailValidationRejectsDoubleAt() {
        #expect(MailAccountAutodiscovery.isValidEmailAddress("user@example.com"))
        #expect(!MailAccountAutodiscovery.isValidEmailAddress("you@corp.com@evil.com"))
        #expect(!MailAccountAutodiscovery.isValidEmailAddress("user@host")) // single-label domain
        #expect(!MailAccountAutodiscovery.isValidEmailAddress("noatsign.example.com"))
        #expect(!MailAccountAutodiscovery.isValidEmailAddress("@example.com"))
        #expect(!MailAccountAutodiscovery.isValidEmailAddress("user@"))
    }

    @Test("the live autoconfig probe refuses a domain with URL-significant characters (no network)")
    func liveProbeRejectsMalformedDomain() async {
        let probe = LiveMailAutodiscoveryProbe()
        let result = await probe.autoconfigXML(
            forEmailAddress: "you@corp.com",
            domain: "corp.com@evil.com"
        )
        #expect(result == nil)
    }
}

// MARK: - MX parsing and provider mapping

@Suite("MX record parsing and provider mapping")
struct MailServiceMXTests {
    /// Encodes a hostname as a DNS-style sequence of length-prefixed labels
    /// terminated by the root label, prefixed with a 2-byte preference.
    private func mxRData(preference: UInt16, host: String) -> Data {
        var bytes: [UInt8] = [UInt8(preference >> 8), UInt8(preference & 0xFF)]
        for label in host.split(separator: ".") {
            let utf8 = Array(label.utf8)
            bytes.append(UInt8(utf8.count))
            bytes.append(contentsOf: utf8)
        }
        bytes.append(0) // root label
        return Data(bytes)
    }

    @Test("parses preference and exchanger from MX rdata")
    func parsesMXRData() {
        let record = MailMXRDataParser.parse(mxRData(preference: 5, host: "in1-smtp.messagingengine.com"))
        #expect(record?.preference == 5)
        #expect(record?.exchange == "in1-smtp.messagingengine.com")
    }

    @Test("a null-MX (root-only) rdata parses as unusable")
    func parsesNullMX() {
        let record = MailMXRDataParser.parse(Data([0, 0, 0]))
        #expect(record?.isUsable == false)
    }

    @Test("truncated rdata is rejected")
    func rejectsTruncated() {
        #expect(MailMXRDataParser.parse(Data([0])) == nil)
    }

    @Test("the lowest-preference matching exchanger picks the provider")
    func resolvesLowestPreferenceProvider() {
        let records = [
            MailMXRecord(preference: 20, exchange: "backup.self-hosted.example"),
            MailMXRecord(preference: 5, exchange: "in1-smtp.messagingengine.com"),
        ]
        #expect(MailMXProviderResolver.providerDomain(for: records) == "fastmail.com")
    }

    @Test("known provider exchangers map to their canonical domain")
    func mapsKnownProviders() {
        let cases: [(String, String)] = [
            ("aspmx.l.google.com", "gmail.com"),
            ("ogard-no.mail.protection.outlook.com", "outlook.com"),
            ("in1-smtp.messagingengine.com", "fastmail.com"),
            ("mxext1.mailbox.org", "mailbox.org"),
        ]
        for (host, expected) in cases {
            #expect(MailMXProviderResolver.providerDomain(forExchange: host) == expected, "for \(host)")
        }
    }

    @Test("an unknown exchanger resolves to no provider")
    func unknownProviderIsNil() {
        #expect(MailMXProviderResolver.providerDomain(forExchange: "mail.self-hosted.example") == nil)
        #expect(MailMXProviderResolver.providerDomain(for: []) == nil)
    }
}
