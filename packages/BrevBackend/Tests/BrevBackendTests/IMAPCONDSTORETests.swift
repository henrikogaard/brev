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

@Suite("IMAP CONDSTORE (RFC 4551)")
struct IMAPCONDSTORETests {
    // MARK: IMAPSelectedMailbox HIGHESTMODSEQ parsing

    @Test("parses HIGHESTMODSEQ from SELECT OK response")
    func parsesHighestModSeqFromSelectResponse() {
        let responses = [
            "* 172 EXISTS",
            "* 1 RECENT",
            "* OK [UNSEEN 12] Message 12 is first unseen",
            "* OK [UIDVALIDITY 3857529045] UIDs valid",
            "* OK [UIDNEXT 4392] Predicted next UID",
            "* OK [HIGHESTMODSEQ 715194045007]",
            "* FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft)",
            "* OK [PERMANENTFLAGS (\\Deleted \\Seen \\*)] Limited",
        ]
        let mailbox = IMAPSelectedMailbox.parse(from: responses)
        #expect(mailbox.uidValidity == 3_857_529_045)
        #expect(mailbox.highestModSeq == 715_194_045_007)
    }

    @Test("highestModSeq is nil when server does not include HIGHESTMODSEQ")
    func highestModSeqIsNilWithoutCONDSTORE() {
        let responses = [
            "* 10 EXISTS",
            "* OK [UIDVALIDITY 123456] UIDs valid",
        ]
        let mailbox = IMAPSelectedMailbox.parse(from: responses)
        #expect(mailbox.uidValidity == 123_456)
        #expect(mailbox.highestModSeq == nil)
    }

    @Test("parses HIGHESTMODSEQ case-insensitively")
    func parsesHighestModSeqCaseInsensitively() {
        let responses = [
            "* OK [highestmodseq 9999] highest modseq",
        ]
        let mailbox = IMAPSelectedMailbox.parse(from: responses)
        #expect(mailbox.highestModSeq == 9999)
    }
}
