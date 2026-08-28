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

/// A scripted ManageSieve server: returns `lines` in order from `readLine`
/// and records everything the client writes.
private actor MockSieveTransport: ManageSieveSessionTransport {
    private var scriptedLines: [String]
    private(set) var written: [String] = []
    private(set) var didUpgradeTLS = false

    init(lines: [String]) { scriptedLines = lines }

    func connect(to server: MailServerSettings) throws {}
    func upgradeToTLS(server: MailServerSettings) throws { didUpgradeTLS = true }
    func disconnect() {}
    func writeLine(_ line: String) throws { written.append(line) }
    func writeData(_ data: Data) throws {
        written.append(String(data: data, encoding: .utf8) ?? "")
    }

    func readLine() throws -> String {
        guard !scriptedLines.isEmpty else { throw ManageSieveClientError.unexpectedDisconnect }
        return scriptedLines.removeFirst()
    }
}

private let implicitServer = MailServerSettings(
    kind: .manageSieve, host: "sieve.example.org", port: 4190, tlsMode: .implicit
)

private let plan = SieveScriptPlan(
    scriptName: "brev-rules",
    script: "require [\"fileinto\"];\r\nif header :contains \"from\" \"x\" { fileinto \"X\"; }\r\n",
    requiredExtensions: ["fileinto"],
    unsupportedRules: []
)

@Suite("ManageSieveSessionClient")
struct ManageSieveSessionClientTests {
    @Test("uploads and activates a script over a clean session")
    func uploadAndActivate() async throws {
        let mock = MockSieveTransport(lines: [
            "\"IMPLEMENTATION\" \"Test Sieve\"",
            "\"SASL\" \"PLAIN\"",
            "\"SIEVE\" \"fileinto\"",
            "OK", // end of greeting
            "OK", // AUTHENTICATE
            "OK", // PUTSCRIPT
            "OK", // SETACTIVE
        ])
        let client = ManageSieveSessionClient(transport: mock)
        try await client.uploadAndActivate(
            plan: plan, server: implicitServer, username: "alice@x.com", password: "pw"
        )

        let written = await mock.written
        #expect(written.contains { $0.hasPrefix("AUTHENTICATE \"PLAIN\"") })
        #expect(written.contains { $0 == "PUTSCRIPT \"brev-rules\" {\(plan.script.utf8.count)+}" })
        #expect(written.contains(plan.script))
        #expect(written.contains("SETACTIVE \"brev-rules\""))
        #expect(written.contains("LOGOUT"))
        #expect(await mock.didUpgradeTLS == false) // implicit TLS, no STARTTLS
    }

    @Test("performs STARTTLS before auth when the connection is plain")
    func startTLSUpgrade() async throws {
        let mock = MockSieveTransport(lines: [
            "\"STARTTLS\"", "\"SASL\" \"PLAIN\"", "OK", // pre-TLS greeting
            "OK", // STARTTLS
            "\"SASL\" \"PLAIN\"", "\"SIEVE\" \"fileinto\"", "OK", // post-TLS greeting
            "OK", "OK", "OK", // AUTH, PUTSCRIPT, SETACTIVE
        ])
        let client = ManageSieveSessionClient(transport: mock)
        try await client.uploadAndActivate(
            plan: plan,
            server: MailServerSettings(kind: .imap, host: "x", port: 4190, tlsMode: .startTLS),
            username: "a", password: "b"
        )
        #expect(await mock.didUpgradeTLS)
        #expect(await mock.written.contains("STARTTLS"))
    }

    @Test("a rejected PUTSCRIPT fails closed")
    func putScriptRejected() async {
        let mock = MockSieveTransport(lines: [
            "\"SASL\" \"PLAIN\"", "OK", // greeting
            "OK", // AUTHENTICATE
            "NO \"Script has errors\"", // PUTSCRIPT rejected
        ])
        let client = ManageSieveSessionClient(transport: mock)
        await #expect(throws: ManageSieveClientError.self) {
            try await client.uploadAndActivate(
                plan: plan, server: implicitServer, username: "a", password: "b"
            )
        }
    }

    @Test("a failed authentication surfaces, not a script upload")
    func authFailed() async {
        let mock = MockSieveTransport(lines: [
            "\"SASL\" \"PLAIN\"", "OK", // greeting
            "NO \"Invalid credentials\"", // AUTHENTICATE rejected
        ])
        let client = ManageSieveSessionClient(transport: mock)
        await #expect(throws: ManageSieveClientError.self) {
            try await client.uploadAndActivate(
                plan: plan, server: implicitServer, username: "a", password: "b"
            )
        }
        #expect(await mock.written.contains { $0.hasPrefix("PUTSCRIPT") } == false)
    }
}
