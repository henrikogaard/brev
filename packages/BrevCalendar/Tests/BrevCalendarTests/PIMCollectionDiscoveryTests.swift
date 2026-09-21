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
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing

@Suite("PIMDAVCollectionDiscovery")
struct PIMDAVCollectionDiscoveryTests {
    /// Returns scripted responses in order and records every request.
    private final class ScriptedTransport: PIMDAVTransport, @unchecked Sendable {
        struct Step {
            let status: Int
            let headers: [String: String]
            let body: Data

            static func response(
                _ status: Int,
                headers: [String: String] = [:],
                body: String = ""
            ) -> Step {
                Step(status: status, headers: headers, body: Data(body.utf8))
            }
        }

        private(set) var requests: [URLRequest] = []
        private var steps: [Step]

        init(steps: [Step]) { self.steps = steps }

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            requests.append(request)
            guard !steps.isEmpty else {
                throw URLError(.cannotConnectToHost)
            }
            let step = steps.removeFirst()
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: step.status,
                httpVersion: nil,
                headerFields: step.headers
            )!
            return (step.body, response)
        }
    }

    private static let credential = CalDAVCredential.basic(
        username: "henrik",
        password: "app-password"
    )

    private static func source(
        kind: PIMSourceKind = .calendar,
        provider: PIMSourceProvider = .calDAV,
        principal: String? = "https://dav.example.com/principals/henrik/"
    ) -> PIMSource {
        PIMSource(
            id: "pim-test",
            kind: kind,
            provider: provider,
            displayName: "DAV",
            endpointURL: URL(string: "https://dav.example.com/dav/"),
            principalURL: principal.flatMap { URL(string: $0) },
            credentialAccount: "pim-source-pim-test",
            status: .ready
        )
    }

    private static let calendarHomeSet = """
    <?xml version="1.0" encoding="utf-8"?>
    <d:multistatus xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav">
      <d:response>
        <d:href>/principals/henrik/</d:href>
        <d:propstat>
          <d:prop>
            <cal:calendar-home-set><d:href>/calendars/henrik/</d:href></cal:calendar-home-set>
          </d:prop>
          <d:status>HTTP/1.1 200 OK</d:status>
        </d:propstat>
      </d:response>
    </d:multistatus>
    """

    private static let addressbookHomeSet = """
    <?xml version="1.0" encoding="utf-8"?>
    <d:multistatus xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
      <d:response>
        <d:href>/principals/henrik/</d:href>
        <d:propstat>
          <d:prop>
            <card:addressbook-home-set><d:href>/addressbooks/henrik/</d:href></card:addressbook-home-set>
          </d:prop>
          <d:status>HTTP/1.1 200 OK</d:status>
        </d:propstat>
      </d:response>
    </d:multistatus>
    """

    private static let calendarListing = """
    <?xml version="1.0" encoding="utf-8"?>
    <d:multistatus xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/" xmlns:ical="http://apple.com/ns/ical/">
      <d:response>
        <d:href>/calendars/henrik/</d:href>
        <d:propstat>
          <d:prop>
            <d:resourcetype><d:collection/></d:resourcetype>
            <d:displayname>Henrik calendars</d:displayname>
          </d:prop>
          <d:status>HTTP/1.1 200 OK</d:status>
        </d:propstat>
      </d:response>
      <d:response>
        <d:href>/calendars/henrik/personal/</d:href>
        <d:propstat>
          <d:prop>
            <d:resourcetype><d:collection/><cal:calendar/></d:resourcetype>
            <d:displayname>Personal</d:displayname>
            <ical:calendar-color>#1a73e8</ical:calendar-color>
            <cs:getctag>ctag-42</cs:getctag>
            <d:sync-token>https://dav.example.com/sync/99</d:sync-token>
            <d:current-user-privilege-set>
              <d:privilege><d:all/></d:privilege>
            </d:current-user-privilege-set>
          </d:prop>
          <d:status>HTTP/1.1 200 OK</d:status>
        </d:propstat>
      </d:response>
      <d:response>
        <d:href>/calendars/henrik/shared/</d:href>
        <d:propstat>
          <d:prop>
            <d:resourcetype><d:collection/><cal:calendar/></d:resourcetype>
            <d:displayname>Shared team</d:displayname>
            <d:getetag>"etag-7"</d:getetag>
            <d:supported-report-set>
              <d:supported-report><d:report><d:sync-collection/></d:report></d:supported-report>
            </d:supported-report-set>
            <d:current-user-privilege-set>
              <d:privilege><d:read/></d:privilege>
            </d:current-user-privilege-set>
          </d:prop>
          <d:status>HTTP/1.1 200 OK</d:status>
        </d:propstat>
        <d:propstat>
          <d:prop><cs:getctag/></d:prop>
          <d:status>HTTP/1.1 404 Not Found</d:status>
        </d:propstat>
      </d:response>
      <d:response>
        <d:href>/calendars/henrik/outbox/</d:href>
        <d:propstat>
          <d:prop>
            <d:resourcetype><d:collection/><cal:schedule-outbox/></d:resourcetype>
            <d:displayname>Outbox</d:displayname>
          </d:prop>
          <d:status>HTTP/1.1 200 OK</d:status>
        </d:propstat>
      </d:response>
    </d:multistatus>
    """

    private static let addressbookListing = """
    <?xml version="1.0" encoding="utf-8"?>
    <d:multistatus xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
      <d:response>
        <d:href>/addressbooks/henrik/</d:href>
        <d:propstat>
          <d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop>
          <d:status>HTTP/1.1 200 OK</d:status>
        </d:propstat>
      </d:response>
      <d:response>
        <d:href>/addressbooks/henrik/default/</d:href>
        <d:propstat>
          <d:prop>
            <d:resourcetype><d:collection/><card:addressbook/></d:resourcetype>
            <d:displayname>Contacts</d:displayname>
            <d:current-user-privilege-set>
              <d:privilege><d:write/></d:privilege>
            </d:current-user-privilege-set>
          </d:prop>
          <d:status>HTTP/1.1 200 OK</d:status>
        </d:propstat>
      </d:response>
    </d:multistatus>
    """

    @Test("Calendar discovery walks principal to home set to collections")
    func calendarDiscovery() async throws {
        let transport = ScriptedTransport(steps: [
            .response(207, body: Self.calendarHomeSet),
            .response(207, body: Self.calendarListing)
        ])
        let discovery = PIMDAVCollectionDiscovery(transport: transport)
        let collections = try await discovery.discoverCollections(
            for: Self.source(),
            credential: Self.credential
        )

        // Two PROPFINDs: Depth:0 on the principal, Depth:1 on the home set.
        #expect(transport.requests.count == 2)
        #expect(transport.requests[0].httpMethod == "PROPFIND")
        #expect(transport.requests[0].value(forHTTPHeaderField: "Depth") == "0")
        #expect(transport.requests[0].url?.absoluteString == "https://dav.example.com/principals/henrik/")
        #expect(transport.requests[1].value(forHTTPHeaderField: "Depth") == "1")
        #expect(transport.requests[1].url?.absoluteString == "https://dav.example.com/calendars/henrik/")
        #expect(
            transport.requests[0].value(forHTTPHeaderField: "Authorization")?
                .hasPrefix("Basic ") == true
        )

        // The home set container and the schedule outbox are skipped.
        #expect(collections.count == 2)
        let personal = try #require(collections.first {
            $0.providerKey == "https://dav.example.com/calendars/henrik/personal/"
        })
        #expect(personal.displayName == "Personal")
        #expect(personal.colorHex == "#1a73e8")
        #expect(personal.isReadOnly == false)
        #expect(personal.supportsSyncToken == true)
        #expect(personal.providerVersion == "ctag-42")

        let shared = try #require(collections.first {
            $0.providerKey == "https://dav.example.com/calendars/henrik/shared/"
        })
        #expect(shared.displayName == "Shared team")
        #expect(shared.isReadOnly == true)
        #expect(shared.supportsSyncToken == true)
        // getctag was 404 for this collection; getetag is the fallback.
        #expect(shared.providerVersion == "\"etag-7\"")
    }

    @Test("CardDAV discovery uses the addressbook home set")
    func cardDAVDiscovery() async throws {
        let transport = ScriptedTransport(steps: [
            .response(207, body: Self.addressbookHomeSet),
            .response(207, body: Self.addressbookListing)
        ])
        let discovery = PIMDAVCollectionDiscovery(transport: transport)
        let collections = try await discovery.discoverCollections(
            for: Self.source(kind: .contacts, provider: .cardDAV),
            credential: Self.credential
        )

        #expect(collections.count == 1)
        #expect(
            collections[0].providerKey
                == "https://dav.example.com/addressbooks/henrik/default/"
        )
        #expect(collections[0].displayName == "Contacts")
        #expect(collections[0].isReadOnly == false)
    }

    @Test("Missing principal falls back to an endpoint probe")
    func endpointProbeFallback() async throws {
        let bothProps = """
        <?xml version="1.0" encoding="utf-8"?>
        <d:multistatus xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav">
          <d:response>
            <d:href>/dav/</d:href>
            <d:propstat>
              <d:prop>
                <d:current-user-principal><d:href>/principals/henrik/</d:href></d:current-user-principal>
              </d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
          </d:response>
        </d:multistatus>
        """
        let transport = ScriptedTransport(steps: [
            .response(207, body: bothProps),
            .response(207, body: Self.calendarHomeSet),
            .response(207, body: Self.calendarListing)
        ])
        let discovery = PIMDAVCollectionDiscovery(transport: transport)
        let collections = try await discovery.discoverCollections(
            for: Self.source(principal: nil),
            credential: Self.credential
        )

        #expect(transport.requests.count == 3)
        #expect(transport.requests[0].url?.absoluteString == "https://dav.example.com/dav/")
        #expect(transport.requests[1].url?.absoluteString == "https://dav.example.com/principals/henrik/")
        #expect(collections.count == 2)
    }

    @Test("A source without a home set is unsupported")
    func missingHomeSet() async throws {
        let empty = """
        <?xml version="1.0" encoding="utf-8"?>
        <d:multistatus xmlns:d="DAV:">
          <d:response>
            <d:href>/dav/</d:href>
            <d:propstat>
              <d:prop><d:displayname>root</d:displayname></d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
          </d:response>
        </d:multistatus>
        """
        let transport = ScriptedTransport(steps: [
            .response(207, body: empty),
            .response(207, body: empty)
        ])
        let discovery = PIMDAVCollectionDiscovery(transport: transport)
        await #expect(throws: PIMDAVConnectError.unsupportedServer) {
            try await discovery.discoverCollections(
                for: Self.source(principal: nil),
                credential: Self.credential
            )
        }
    }

    @Test("Authentication failure surfaces as authenticationRequired")
    func authenticationRequired() async throws {
        let transport = ScriptedTransport(steps: [.response(401)])
        let discovery = PIMDAVCollectionDiscovery(transport: transport)
        await #expect(throws: PIMDAVConnectError.authenticationRequired) {
            try await discovery.discoverCollections(
                for: Self.source(),
                credential: Self.credential
            )
        }
    }

    @Test("A cross-origin redirect is never followed with credentials")
    func crossOriginRedirect() async throws {
        let transport = ScriptedTransport(steps: [
            .response(
                301,
                headers: ["Location": "https://evil.example.net/principals/"]
            )
        ])
        let discovery = PIMDAVCollectionDiscovery(transport: transport)
        await #expect(throws: PIMDAVConnectError.crossOriginRedirect) {
            try await discovery.discoverCollections(
                for: Self.source(),
                credential: Self.credential
            )
        }
        #expect(transport.requests.count == 1)
    }
}

@Suite("GooglePIMCollectionDiscovery")
struct GooglePIMCollectionDiscoveryTests {
    private final class ScriptedTransport: PIMDAVTransport, @unchecked Sendable {
        private(set) var requests: [URLRequest] = []
        private var steps: [(status: Int, body: String)]

        init(steps: [(status: Int, body: String)]) { self.steps = steps }

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            requests.append(request)
            guard !steps.isEmpty else {
                throw URLError(.cannotConnectToHost)
            }
            let step = steps.removeFirst()
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: step.status,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(step.body.utf8), response)
        }
    }

    private static let calendarPage1 = """
    {
      "nextPageToken": "page-2",
      "items": [
        {
          "id": "primary-id",
          "summary": "Henrik",
          "primary": true,
          "accessRole": "owner",
          "backgroundColor": "#1a73e8",
          "etag": "etag-1",
          "selected": true
        },
        {
          "id": "team-id",
          "summary": "Team",
          "summaryOverride": "Team (work)",
          "accessRole": "reader",
          "hidden": true,
          "etag": "etag-2"
        },
        {
          "id": "deleted-id",
          "summary": "Old",
          "deleted": true
        }
      ]
    }
    """

    private static let calendarPage2 = """
    {
      "items": [
        {
          "id": "family-id",
          "summary": "Family",
          "accessRole": "writer",
          "selected": false
        }
      ]
    }
    """

    @Test("Calendar list pages are followed and mapped")
    func calendarList() async throws {
        let transport = ScriptedTransport(steps: [
            (200, Self.calendarPage1),
            (200, Self.calendarPage2)
        ])
        let discovery = GooglePIMCollectionDiscovery(transport: transport)
        let collections = try await discovery.discoverCollections(
            kind: .calendar,
            accessToken: "token-1"
        )

        #expect(transport.requests.count == 2)
        #expect(
            transport.requests[0].url?.absoluteString
                == "https://www.googleapis.com/calendar/v3/users/me/calendarList?maxResults=250&showHidden=true"
        )
        #expect(
            transport.requests[1].url?.query?.contains("pageToken=page-2") == true
        )
        #expect(
            transport.requests[0].value(forHTTPHeaderField: "Authorization")
                == "Bearer token-1"
        )

        // The deleted entry is skipped.
        #expect(collections.count == 3)
        let primary = try #require(collections.first {
            $0.providerKey == "primary-id"
        })
        #expect(primary.isPrimary == true)
        #expect(primary.isReadOnly == false)
        #expect(primary.colorHex == "#1a73e8")
        #expect(primary.providerVersion == "etag-1")
        #expect(primary.supportsSyncToken == true)

        let team = try #require(collections.first { $0.providerKey == "team-id" })
        #expect(team.displayName == "Team (work)")
        #expect(team.isReadOnly == true)
        #expect(team.initiallyHidden == true)

        let family = try #require(collections.first {
            $0.providerKey == "family-id"
        })
        #expect(family.isReadOnly == false)
        #expect(family.initiallyHidden == true)
    }

    @Test("Contact groups map system groups to read-only collections")
    func contactGroups() async throws {
        let body = """
        {
          "contactGroups": [
            {
              "resourceName": "contactGroups/myContacts",
              "name": "myContacts",
              "formattedName": "My Contacts",
              "groupType": "SYSTEM_CONTACT_GROUP",
              "etag": "g-etag-1"
            },
            {
              "resourceName": "contactGroups/abc123",
              "name": "friends",
              "formattedName": "Friends",
              "groupType": "USER_CONTACT_GROUP"
            }
          ]
        }
        """
        let transport = ScriptedTransport(steps: [(200, body)])
        let discovery = GooglePIMCollectionDiscovery(transport: transport)
        let collections = try await discovery.discoverCollections(
            kind: .contacts,
            accessToken: "token-1"
        )

        #expect(transport.requests[0].url?.host() == "people.googleapis.com")
        #expect(collections.count == 2)
        #expect(collections[0].isPrimary == true)
        #expect(collections[0].isReadOnly == true)
        #expect(collections[0].displayName == "My Contacts")
        #expect(collections[1].isReadOnly == false)
        #expect(collections[1].displayName == "Friends")
    }

    @Test("Rejected tokens surface as authenticationRequired")
    func unauthorized() async throws {
        let transport = ScriptedTransport(steps: [(401, "{}")])
        let discovery = GooglePIMCollectionDiscovery(transport: transport)
        await #expect(
            throws: PIMCollectionDiscoveryError.authenticationRequired
        ) {
            try await discovery.discoverCollections(
                kind: .calendar,
                accessToken: "bad"
            )
        }
    }

    @Test("Malformed JSON surfaces as invalidResponse")
    func malformed() async throws {
        let transport = ScriptedTransport(steps: [(200, "not json")])
        let discovery = GooglePIMCollectionDiscovery(transport: transport)
        await #expect(throws: PIMCollectionDiscoveryError.invalidResponse) {
            try await discovery.discoverCollections(
                kind: .calendar,
                accessToken: "token-1"
            )
        }
    }
}
