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

#if os(macOS)
import AppKit
import SwiftUI
#endif
import BrevBackend
@testable import BrevMail
import Foundation
import Testing

@Suite("MessageHeaderAnalyzer")
struct MessageHeaderAnalyzerTests {
    #if os(macOS)
    @Test("the shared reader banner occupies space only when there is a warning")
    @MainActor
    func renderedBanner() {
        let header = MessageHeader(id: "m", threadID: "t", folderID: "inbox",
                                   from: .init(name: "Contoso.example", email: "friend@northwind.example"),
                                   subject: "", snippet: "", date: .now)
        func height(written: Set<String>) -> CGFloat {
            let host = NSHostingView(rootView: VStack(spacing: 0) {
                SenderWarningBanner(header: header, authenticationResults: nil)
                Color.clear.frame(height: 1)
            }.environment(\.senderWarningHistory, SenderWarningHistory(written: written))
                .frame(width: 320).fixedSize(horizontal: false, vertical: true))
            return host.fittingSize.height
        }
        #expect(height(written: []) > height(written: ["friend@northwind.example"]) + 10)
    }
    #endif

    @Test("sender warning disclosures are localized in Norwegian", arguments: [
        "Sender address: %@",
        "Show sender details",
        "The sender’s domain could not be verified",
        "The name and sender domain don’t match",
        "This message came from %@, which may be impersonating %@.",
        "The authentication header reports a DMARC failure. Check the address before replying.",
        "The display name mentions a different domain from the sender’s address.",
        "The name or domain resembles a familiar sender. Check the spelling before replying."
    ])
    func localizedDetails(key: String) throws {
        let strings = try LocalizationCatalogTestSupport.loadCatalogStrings()
        let entry = try #require(strings[key] as? [String: Any])
        let locales = try #require(entry["localizations"] as? [String: Any])
        let nb = try #require(locales["nb"] as? [String: Any])
        let value = (nb["stringUnit"] as? [String: Any])?["value"] as? String
        #expect(value?.isEmpty == false)
        #expect(value != key)
    }

    @Test("cached Sent contributes only recipients of messages from an owned address")
    func sentHistory() {
        func header(from: String, to: String) -> MessageHeader {
            MessageHeader(id: to, threadID: "t", folderID: "sent", from: .init(email: from),
                          replyTo: [.init(email: "not-a-recipient@example.org")],
                          to: [.init(email: to)], subject: "", snippet: "", date: .now)
        }
        let headers = [header(from: "Mine@example.org", to: "FRIEND@example.org"),
                       header(from: "unknown@example.org", to: "someone@example.org")]
        #expect(SenderWarningHistory.recipients(of: headers, ownAddresses: ["mine@example.org"]) == ["friend@example.org"])
    }

    @Test("previously written addresses are exact exemptions; other senders still show the reason")
    func warningPrecedence() {
        func check(_ email: String, name: String?, auth: String? = nil) -> SenderAuthWarning? {
            let header = MessageHeader(id: "m", threadID: "t", folderID: "inbox",
                                       from: .init(name: name, email: email), subject: "", snippet: "", date: .now)
            return MessageHeaderAnalyzer.warning(for: header, authenticationResults: auth,
                                                 writtenAddresses: ["friend@northwind.example"],
                                                 knownDomains: ["northwind.example"])
        }
        #expect(check("FRIEND@northwind.example", name: "Different.example") == nil)
        #expect(check("FRIEND@northwind.example", name: nil, auth: "mx.example; dmarc=fail") == .dmarcFail)
        #expect(check("other@northwind.example", name: nil, auth: "mx.example; dmarc=fail") == .dmarcFail)
        #expect(check("person@unrelated.example", name: "northwind.example") == .displayNameMismatch)
        #expect(check("person@northwimd.example", name: nil) == .lookAlikeDomain("northwind.example"))
        #expect(check("info@mail.paypal.com", name: "PayPal") == nil)
    }

    @Test("internationalized display-name domains are compared across Unicode and IDNA spellings")
    func internationalizedDisplayDomain() {
        func differs(_ name: String, _ email: String) -> Bool {
            MessageHeaderAnalyzer.hasDisplayNameMismatch(from: .init(name: name, email: email))
        }
        #expect(differs("пример.рф", "a@example.test"))
        #expect(!differs("пример.рф", "a@mail.xn--e1afmkfd.xn--p1ai"))
        #expect(!differs("Release 2.3.1", "a@example.test"))
    }

    @Test("DMARC fail and permerror are flagged; pass and transient temperror are not")
    func dmarcFailureDetection() {
        #expect(MessageHeaderAnalyzer.hasDMARCFail(in: "mx.example.com; dmarc=fail header.from=evil.test"))
        // permerror (malformed/unevaluable DMARC) was previously missed.
        #expect(MessageHeaderAnalyzer.hasDMARCFail(in: "mx.example.com; spf=pass; dmarc=permerror"))
        #expect(!MessageHeaderAnalyzer.hasDMARCFail(in: "mx.example.com; dmarc=pass"))
        // temperror is a transient DNS condition, not a spoof signal.
        #expect(!MessageHeaderAnalyzer.hasDMARCFail(in: "mx.example.com; dmarc=temperror"))
        #expect(!MessageHeaderAnalyzer.hasDMARCFail(in: nil))
    }
}
