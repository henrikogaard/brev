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

@testable import BrevCalendar
import Foundation
import Testing

@Suite("CalDAVConfiguration")
struct CalDAVConfigurationTests {
    @Test("config round-trips through Codable")
    func codableRoundTrip() throws {
        let config = CalDAVConfiguration(
            principalURL: URL(string: "https://caldav.example.com/principals/user/")!,
            authMode: .oauth2,
            email: "user@example.com"
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(CalDAVConfiguration.self, from: data)
        #expect(decoded == config)
    }
}

@Suite("CalDAVDiscovery")
struct CalDAVDiscoveryTests {
    @Test("unknown domain uses well-known discovery method")
    func unknownDomainUsesWellKnown() {
        let result = CalDAVDiscovery.discover(for: "user@custom-company.example")
        #expect(result.discoveryMethod == .wellKnown)
        #expect(result.caldav?.principalURL.host == "custom-company.example")
    }

    @Test("invalid email without @ returns manual method and nil configs")
    func invalidEmailReturnsManual() {
        let result = CalDAVDiscovery.discover(for: "notanemail")
        #expect(result.discoveryMethod == .manual)
        #expect(result.caldav == nil)
        #expect(result.carddav == nil)
    }

    @Test("malformed domain returns manual method and nil configs")
    func malformedDomainReturnsManual() {
        let result = CalDAVDiscovery.discover(for: "person@bad domain")
        #expect(result.discoveryMethod == .manual)
        #expect(result.caldav == nil)
        #expect(result.carddav == nil)
    }

    @Test("semantically invalid domains return manual method and nil configs")
    func semanticallyInvalidDomainsReturnManual() {
        for domain in ["example..com", "-bad.com"] {
            let result = CalDAVDiscovery.discover(for: "person@\(domain)")
            #expect(result.discoveryMethod == .manual)
            #expect(result.caldav == nil)
            #expect(result.carddav == nil)
        }
    }

    @Test("valid domain still produces well-known endpoints")
    func validDomainProducesWellKnownEndpoints() throws {
        let result = CalDAVDiscovery.discover(for: "person@example.com")
        #expect(result.discoveryMethod == .wellKnown)
        #expect(try #require(result.caldav).principalURL.absoluteString == "https://example.com/.well-known/caldav")
        #expect(try #require(result.carddav).principalURL.absoluteString == "https://example.com/.well-known/carddav")
    }

    @Test("probe URLs include well-known and caldav subdomain variants")
    func probeURLsIncludeVariants() {
        let urls = CalDAVDiscovery.probeURLs(for: "example.com")
        #expect(urls.count >= 2)
        #expect(urls.contains { $0.absoluteString.contains("well-known/caldav") })
    }

    @Test("malformed probe domain returns no endpoints")
    func malformedProbeDomainReturnsNoEndpoints() {
        #expect(CalDAVDiscovery.probeURLs(for: "bad domain").isEmpty)
    }

    @Test("empty domains return no endpoints")
    func emptyDomainsReturnNoEndpoints() {
        let result = CalDAVDiscovery.discover(for: "person@")
        #expect(result.discoveryMethod == .manual)
        #expect(result.caldav == nil)
        #expect(result.carddav == nil)
        #expect(CalDAVDiscovery.probeURLs(for: "").isEmpty)
    }

    @Test("semantically invalid probe domains return no endpoints")
    func semanticallyInvalidProbeDomainsReturnNoEndpoints() {
        for domain in ["example..com", "-bad.com"] {
            #expect(CalDAVDiscovery.probeURLs(for: domain).isEmpty)
        }
    }
}
