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

@testable import BrevMail
import Foundation
import Testing

@Suite("MessageLinkSchemePolicy")
struct MessageLinkSchemePolicyTests {
    @Test("opens ordinary web and communication links", arguments: [
        "https://example.org/path?q=1",
        "http://example.org",
        "mailto:alex@example.org",
        "tel:+155501000",
        "sms:+155501000",
    ])
    func opensSafeSchemes(_ string: String) throws {
        let url = try #require(URL(string: string))
        #expect(MessageLinkSchemePolicy.isOpenable(url))
    }

    @Test("communication links are recognized but never opened directly", arguments: [
        "mailto:alex@example.org",
        "tel:+155501000",
        "sms:+155501000",
    ])
    func communicationLinksRequireConfirmationOrDeny(_ string: String) throws {
        let url = try #require(URL(string: string))
        #expect(!MessageLinkSchemePolicy.isDirectlyOpenable(url))
    }

    @Test("drops code-execution, local-resource, and unknown schemes", arguments: [
        "javascript:alert(1)",
        "JavaScript:alert(1)", // case-insensitive
        "vbscript:msgbox(1)",
        "data:text/html,<script>alert(1)</script>",
        "file:///etc/passwd",
        "blob:https://example.org/uuid",
        "about:blank",
        "view-source:https://example.org",
        "custom-handler://example.org/action",
        "itms-services://example.org/install",
    ])
    func dropsDangerousSchemes(_ string: String) throws {
        let url = try #require(URL(string: string))
        #expect(!MessageLinkSchemePolicy.isOpenable(url))
    }

    @Test("drops a schemeless (relative) link that can't be resolved without a base") func dropsSchemelessLink() throws {
        let url = try #require(URL(string: "/relative/path"))
        #expect(!MessageLinkSchemePolicy.isOpenable(url))
    }
}
