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

/// Exercises the real NetworkManageSieveSessionTransport (its CRLF line
/// buffering and write framing) end-to-end with the session client, over a
/// scripted in-memory socket — the same approach the IMAP/SMTP transports use.
@Suite("NetworkManageSieveSessionTransport")
struct NetworkManageSieveTransportTests {
    @Test("drives a full upload-and-activate over the scripted socket")
    func fullSessionOverSocket() async throws {
        let socket = ScriptedSocket(lines: [
            "\"IMPLEMENTATION\" \"Test Sieve\"",
            "\"SASL\" \"PLAIN\"",
            "\"SIEVE\" \"fileinto\"",
            "OK", // greeting
            "OK", // AUTHENTICATE
            "OK", // PUTSCRIPT
            "OK", // SETACTIVE
        ])
        let transport = NetworkManageSieveSessionTransport(socket: socket)
        let client = ManageSieveSessionClient(transport: transport)
        let plan = SieveScriptPlan(
            scriptName: "brev-rules",
            script: "require [\"fileinto\"];\r\n",
            requiredExtensions: ["fileinto"],
            unsupportedRules: []
        )

        try await client.uploadAndActivate(
            plan: plan,
            server: MailServerSettings(kind: .manageSieve, host: "sieve.x", port: 4190, tlsMode: .implicit),
            username: "alice@x.com",
            password: "pw"
        )

        let sent = socket.sentLines.joined()
        #expect(sent.contains("AUTHENTICATE \"PLAIN\""))
        #expect(sent.contains("PUTSCRIPT \"brev-rules\""))
        #expect(sent.contains("require [\"fileinto\"];"))
        #expect(sent.contains("SETACTIVE \"brev-rules\""))
        #expect(sent.contains("LOGOUT"))
    }

    @Test("PUTSCRIPT writes exactly the declared script literal bytes")
    func putScriptWritesExactLiteralBytes() async throws {
        let socket = ScriptedSocket(lines: [
            "\"SASL\" \"PLAIN\"",
            "OK",
            "OK",
            "OK",
            "OK",
        ])
        let transport = NetworkManageSieveSessionTransport(socket: socket)
        let client = ManageSieveSessionClient(transport: transport)
        let script = "require [\"fileinto\"];\r\n"
        let plan = SieveScriptPlan(
            scriptName: "brev-rules",
            script: script,
            requiredExtensions: ["fileinto"],
            unsupportedRules: []
        )

        try await client.uploadAndActivate(
            plan: plan,
            server: MailServerSettings(kind: .manageSieve, host: "sieve.x", port: 4190, tlsMode: .implicit),
            username: "alice@x.com",
            password: "pw"
        )

        let writes = socket.sentLines
        let header = "PUTSCRIPT \"brev-rules\" {\(script.utf8.count)+}\r\n"
        let headerIndex = try #require(writes.firstIndex(of: header))
        #expect(writes[headerIndex + 1] == script)
    }

    @Test("readLine reassembles a response split across socket chunks")
    func reassemblesSplitLine() async throws {
        // "OK\r\n" delivered in two reads, proving the line buffer joins them.
        let socket = ScriptedSocket(chunks: [Data("O".utf8), Data("K\r\n".utf8)])
        let transport = NetworkManageSieveSessionTransport(socket: socket)
        let line = try await transport.readLine()
        #expect(line == "OK")
    }
}
