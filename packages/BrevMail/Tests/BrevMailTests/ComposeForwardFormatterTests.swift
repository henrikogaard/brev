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

import BrevBackend
@testable import BrevMail
import Foundation
import Testing

@Suite("ComposeForwardFormatter")
struct ComposeForwardFormatterTests {
    @Test("forward subject adds prefix once")
    func forwardSubjectAddsPrefixOnce() {
        #expect(ComposeForwardFormatter.subject(for: "Project notes") == "Fwd: Project notes")
        #expect(ComposeForwardFormatter.subject(for: "  fwd: Project notes  ") == "fwd: Project notes")
    }

    @Test("forward body includes original metadata and snippet")
    func forwardBodyIncludesOriginalMetadataAndSnippet() {
        let header = MessageHeader(
            id: "m1",
            threadID: "t1",
            folderID: "inbox",
            from: Correspondent(name: "Alex Chen", email: "alex@example.org"),
            to: [Correspondent(name: "Henrik", email: "henrik@example.org")],
            cc: [Correspondent(email: "team@example.org")],
            subject: "Launch checklist",
            snippet: "Let's review the launch checklist before Friday.",
            date: Date(timeIntervalSince1970: 1_779_960_600)
        )

        let body = ComposeForwardFormatter.body(for: header)

        #expect(body == """


        ---------- Forwarded message ----------
        From: Alex Chen <alex@example.org>
        Date: 28 May 2026 at 09:30 UTC
        Subject: Launch checklist
        To: Henrik <henrik@example.org>
        Cc: team@example.org

        Let's review the launch checklist before Friday.
        """)
    }

    @Test("forward body omits empty recipient and snippet lines")
    func forwardBodyOmitsEmptyRecipientAndSnippetLines() {
        let header = MessageHeader(
            id: "m1",
            threadID: "t1",
            folderID: "inbox",
            from: Correspondent(email: "alex@example.org"),
            subject: "   ",
            snippet: "   ",
            date: Date(timeIntervalSince1970: 1_779_960_600)
        )

        let body = ComposeForwardFormatter.body(for: header)

        #expect(body == """


        ---------- Forwarded message ----------
        From: alex@example.org
        Date: 28 May 2026 at 09:30 UTC
        Subject: (no subject)
        """)
    }
}
