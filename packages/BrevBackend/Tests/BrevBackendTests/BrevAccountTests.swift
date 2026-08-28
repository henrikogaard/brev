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

@Suite("BrevAccount")
struct BrevAccountTests {
    @Test("new accounts default to IMAP SMTP backend badge")
    func defaultsToIMAPSMTPBackendBadge() {
        let account = BrevAccount(
            id: "account-1",
            displayName: "Henrik",
            emailAddress: "henrik@example.org"
        )

        #expect(account.backendIdentifier == "imap-smtp")
        #expect(account.backendDisplayName == "IMAP/SMTP")
    }

    @Test("custom backend badge survives coding")
    func customBackendBadgeSurvivesCoding() throws {
        let account = BrevAccount(
            id: "demo-account",
            displayName: "Demo",
            emailAddress: "demo@example.org",
            backendIdentifier: "demo",
            backendDisplayName: "Demo"
        )

        let data = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(BrevAccount.self, from: data)

        #expect(decoded == account)
    }

    @Test("stored accounts missing backend metadata migrate to IMAP SMTP")
    func storedAccountsMissingBackendMetadataMigrateToIMAPSMTP() throws {
        let data = Data("""
        {
          "id": "legacy-account",
          "displayName": "Legacy",
          "emailAddress": "legacy@example.org"
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(BrevAccount.self, from: data)

        #expect(decoded.backendIdentifier == BrevAccount.imapSMTPBackendIdentifier)
        #expect(decoded.backendDisplayName == BrevAccount.imapSMTPBackendDisplayName)
    }

    @Test("stored accounts derive a missing display name from their backend identifier")
    func storedAccountsDeriveMissingDisplayNameFromBackendIdentifier() throws {
        let data = Data("""
        {
          "id": "gmail-account",
          "displayName": "Google user",
          "emailAddress": "person@example.org",
          "backendIdentifier": "gmail-api"
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(BrevAccount.self, from: data)

        #expect(decoded.backendIdentifier == BrevAccount.gmailAPIBackendIdentifier)
        #expect(decoded.backendDisplayName == BrevAccount.gmailAPIBackendDisplayName)
    }

    @Test("stored accounts missing an identifier migrate as a consistent IMAP SMTP pair")
    func storedAccountsMissingIdentifierMigrateAsConsistentIMAPSMTPPair() throws {
        let data = Data("""
        {
          "id": "legacy-account",
          "displayName": "Legacy user",
          "emailAddress": "legacy@example.org",
          "backendDisplayName": "Retired provider"
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(BrevAccount.self, from: data)

        #expect(decoded.backendIdentifier == BrevAccount.imapSMTPBackendIdentifier)
        #expect(decoded.backendDisplayName == BrevAccount.imapSMTPBackendDisplayName)
    }
}
