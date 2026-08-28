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

@Suite("ManageSieve capabilities")
struct ManageSieveCapabilitiesTests {
    @Test("parses SASL, SIEVE, STARTTLS, and IMPLEMENTATION")
    func parsesGreeting() {
        let lines = [
            "\"IMPLEMENTATION\" \"Dovecot Pigeonhole\"",
            "\"SASL\" \"PLAIN LOGIN\"",
            "\"SIEVE\" \"fileinto reject envelope vacation\"",
            "\"VERSION\" \"1.0\"",
            "\"STARTTLS\"",
        ]
        let caps = ManageSieveCapabilities.parse(lines)
        #expect(caps.saslMechanisms == ["PLAIN", "LOGIN"])
        #expect(caps.sieveExtensions == ["fileinto", "reject", "envelope", "vacation"])
        #expect(caps.supportsStartTLS)
        #expect(caps.implementation == "Dovecot Pigeonhole")
    }

    @Test("absent STARTTLS and SASL are empty/false")
    func parsesMinimal() {
        let caps = ManageSieveCapabilities.parse(["\"SIEVE\" \"fileinto\""])
        #expect(!caps.supportsStartTLS)
        #expect(caps.saslMechanisms.isEmpty)
        #expect(caps.sieveExtensions == ["fileinto"])
    }
}

@Suite("ManageSieve response parsing")
struct ManageSieveResponseTests {
    @Test("plain OK")
    func parsesOK() {
        let r = ManageSieveResponse.parse("OK")
        #expect(r?.status == .ok)
        #expect(r?.isOK == true)
    }

    @Test("NO with a quoted message")
    func parsesNoMessage() {
        let r = ManageSieveResponse.parse("NO \"Script too large\"")
        #expect(r?.status == .no)
        #expect(r?.message == "Script too large")
    }

    @Test("NO with a response code and message")
    func parsesNoCode() {
        let r = ManageSieveResponse.parse("NO (QUOTA/MAXSCRIPTS) \"Too many scripts\"")
        #expect(r?.status == .no)
        #expect(r?.code == "QUOTA/MAXSCRIPTS")
        #expect(r?.message == "Too many scripts")
    }

    @Test("BYE is recognized")
    func parsesBye() {
        #expect(ManageSieveResponse.parse("BYE \"Connection timed out\"")?.status == .bye)
    }

    @Test("intermediate data lines are not results")
    func ignoresData() {
        #expect(ManageSieveResponse.parse("\"brev-rules\" ACTIVE") == nil)
        #expect(ManageSieveResponse.parse("{42}") == nil)
    }
}

@Suite("ManageSieve commands")
struct ManageSieveCommandTests {
    @Test("AUTHENTICATE PLAIN carries base64 of NUL-user-NUL-pass")
    func authenticatePlain() {
        let command = ManageSieveCommand.authenticatePlain(username: "alice@x.com", password: "secret")
        #expect(command.hasPrefix("AUTHENTICATE \"PLAIN\" \""))
        let base64 = String(command.dropFirst("AUTHENTICATE \"PLAIN\" \"".count).dropLast())
        let decoded = Data(base64Encoded: base64).map { String(decoding: $0, as: UTF8.self) }
        #expect(decoded == "\u{0}alice@x.com\u{0}secret")
    }

    @Test("PUTSCRIPT header uses a non-synchronizing literal with the byte count")
    func putScriptHeader() {
        let script = "require [\"fileinto\"];\r\n" // 21 bytes
        let header = ManageSieveCommand.putScriptHeader(name: "brev-rules", script: script)
        #expect(header == "PUTSCRIPT \"brev-rules\" {\(script.utf8.count)+}")
    }

    @Test("script names are quoted and escaped")
    func quoting() {
        #expect(ManageSieveCommand.setActive(name: "brev-rules") == "SETACTIVE \"brev-rules\"")
        #expect(ManageSieveCommand.deleteScript(name: "a\"b") == "DELETESCRIPT \"a\\\"b\"")
    }
}

@Suite("ManageSieve LISTSCRIPTS parsing")
struct ManageSieveScriptEntryTests {
    @Test("parses name and active flag")
    func parsesEntries() {
        #expect(ManageSieveScriptEntry.parse("\"brev-rules\" ACTIVE")
            == ManageSieveScriptEntry(name: "brev-rules", isActive: true))
        #expect(ManageSieveScriptEntry.parse("\"vacation\"")
            == ManageSieveScriptEntry(name: "vacation", isActive: false))
        #expect(ManageSieveScriptEntry.parse("garbage") == nil)
    }
}
