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

import BrevCalendar
@testable import BrevSettings
import Foundation
import Testing

@Suite("PIMDAVConnectForm")
struct PIMDAVConnectFormTests {
    @Test("a complete discovery form produces a discover request")
    func completeDiscoveryFormProducesDiscoverRequest() {
        var form = PIMDAVConnectForm()
        form.kind = .contacts
        form.endpointMode = .discover
        form.address = "henrik@example.com"
        form.credentialMode = .appPassword
        form.username = "henrik"
        form.password = "app-password"

        #expect(form.isValid)
        let request = form.makeRequest()
        #expect(request?.kind == .contacts)
        #expect(request?.endpoint == .discover(emailAddress: "henrik@example.com"))
        #expect(request?.credential == .basic(username: "henrik", password: "app-password"))
        #expect(request?.displayName == "henrik@example.com")
    }

    @Test("a manual https endpoint with a bearer token is valid")
    func manualHTTPSEndpointWithBearerTokenIsValid() {
        var form = PIMDAVConnectForm()
        form.kind = .calendar
        form.endpointMode = .manual
        form.address = "https://caldav.example.com/dav/"
        form.credentialMode = .bearerToken
        form.bearerToken = "token-123"
        form.displayName = "Work calendar"

        #expect(form.isValid)
        let request = form.makeRequest()
        #expect(request?.endpoint == .manual(URL(string: "https://caldav.example.com/dav/")!))
        #expect(request?.credential == .bearer(token: "token-123"))
        #expect(request?.displayName == "Work calendar")
    }

    @Test("a manual endpoint without a scheme defaults to https")
    func manualEndpointWithoutSchemeDefaultsToHTTPS() {
        var form = PIMDAVConnectForm()
        form.endpointMode = .manual
        form.address = "caldav.example.com/dav"
        form.credentialMode = .bearerToken
        form.bearerToken = "token-123"

        #expect(form.isValid)
        let request = form.makeRequest()
        #expect(request?.endpoint == .manual(URL(string: "https://caldav.example.com/dav")!))
        #expect(request?.displayName == "caldav.example.com")
    }

    @Test("http endpoints are only valid on loopback hosts")
    func httpEndpointsOnlyValidOnLoopback() {
        var form = PIMDAVConnectForm()
        form.endpointMode = .manual
        form.credentialMode = .bearerToken
        form.bearerToken = "token-123"

        form.address = "http://caldav.example.com/dav"
        #expect(form.issues.contains(.httpsRequired))
        #expect(!form.isValid)
        #expect(form.makeRequest() == nil)

        form.address = "http://localhost:8008/dav"
        #expect(form.isValid)
    }

    @Test("discovery rejects addresses without a usable domain")
    func discoveryRejectsAddressesWithoutUsableDomain() {
        var form = PIMDAVConnectForm()
        form.endpointMode = .discover
        form.credentialMode = .appPassword
        form.username = "u"
        form.password = "p"

        form.address = "not-an-email"
        #expect(form.issues.contains(.invalidEmailAddress))

        form.address = "henrik@"
        #expect(form.issues.contains(.invalidEmailAddress))

        form.address = "@example.com"
        #expect(form.issues.contains(.invalidEmailAddress))
    }

    @Test("credential fields are required for the selected mode")
    func credentialFieldsAreRequiredForSelectedMode() {
        var form = PIMDAVConnectForm()
        form.endpointMode = .discover
        form.address = "henrik@example.com"

        form.credentialMode = .appPassword
        #expect(form.issues.contains(.usernameRequired))
        #expect(form.issues.contains(.passwordRequired))

        form.username = "henrik"
        #expect(!form.issues.contains(.usernameRequired))
        #expect(form.issues.contains(.passwordRequired))

        form.credentialMode = .bearerToken
        #expect(form.issues.contains(.tokenRequired))
    }

    @Test("whitespace is trimmed before validation")
    func whitespaceIsTrimmedBeforeValidation() {
        var form = PIMDAVConnectForm()
        form.endpointMode = .discover
        form.address = "  henrik@example.com  "
        form.credentialMode = .appPassword
        form.username = "  henrik "
        form.password = " pw "

        #expect(form.isValid)
        let request = form.makeRequest()
        #expect(request?.endpoint == .discover(emailAddress: "henrik@example.com"))
        #expect(request?.credential == .basic(username: "henrik", password: "pw"))
    }
}
