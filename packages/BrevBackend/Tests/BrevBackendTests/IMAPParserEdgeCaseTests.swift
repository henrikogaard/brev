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

@Suite("IMAP parser edge cases")
struct IMAPParserEdgeCaseTests {
    // MARK: - IMAPAppendResult (parse returns non-optional; empty on failure)

    @Test("append result: missing APPENDUID marker returns empty")
    func appendResultMissingMarker() {
        let result = IMAPAppendResult.parse(from: "A0003 OK APPEND completed")
        #expect(result.uidValidity == nil)
        #expect(result.uid == nil)
    }

    @Test("append result: missing closing bracket returns empty")
    func appendResultMissingBracket() {
        let result = IMAPAppendResult.parse(from: "A0003 OK [APPENDUID 999 42 completed")
        #expect(result.uidValidity == nil)
        #expect(result.uid == nil)
    }

    @Test("append result: non-numeric UID validity gives nil uidValidity")
    func appendResultNonNumericUidValidity() {
        let result = IMAPAppendResult.parse(from: "A0003 OK [APPENDUID abc 42]")
        #expect(result.uidValidity == nil)
        #expect(result.uid == 42)
    }

    @Test("append result: non-numeric UID gives nil uid")
    func appendResultNonNumericUid() {
        let result = IMAPAppendResult.parse(from: "A0003 OK [APPENDUID 999 abc]")
        #expect(result.uidValidity == 999)
        #expect(result.uid == nil)
    }

    @Test("append result: fewer than 2 tokens after marker returns empty")
    func appendResultTooFewTokens() {
        let result = IMAPAppendResult.parse(from: "A0003 OK [APPENDUID 999]")
        #expect(result.uidValidity == nil)
        #expect(result.uid == nil)
    }

    @Test("append result: case insensitive marker")
    func appendResultCaseInsensitive() {
        let result = IMAPAppendResult.parse(from: "A0003 OK [appenduid 999 42]")
        #expect(result.uidValidity == 999)
        #expect(result.uid == 42)
    }

    // Regression: non-ASCII whose uppercase form is LONGER in UTF-8 (U+0250
    // 'ɐ' → 'Ɐ') before the marker used to make indices from `uppercased()`
    // overrun the original string and trap. The parser must not crash and must
    // still read the digits.
    @Test("append result: non-ASCII before the marker does not crash")
    func appendResultNonASCIIBeforeMarker() {
        let result = IMAPAppendResult.parse(from: "A0003 OK [ɐɐɐ] [APPENDUID 999 42]")
        #expect(result.uidValidity == 999)
        #expect(result.uid == 42)
    }

    // MARK: - IMAPSelectedMailbox (UIDVALIDITY / HIGHESTMODSEQ)

    @Test("selected mailbox: parses UIDVALIDITY and HIGHESTMODSEQ")
    func selectedMailboxParsesValidityAndModSeq() {
        let result = IMAPSelectedMailbox.parse(from: [
            "* OK [UIDVALIDITY 12345] UIDs valid",
            "* OK [HIGHESTMODSEQ 98765] CONDSTORE",
        ])
        #expect(result.uidValidity == 12345)
        #expect(result.highestModSeq == 98765)
    }

    // Regression: same cross-string-index trap as APPENDUID, on the SELECT path.
    @Test("selected mailbox: non-ASCII before the markers does not crash")
    func selectedMailboxNonASCIIBeforeMarkers() {
        let result = IMAPSelectedMailbox.parse(from: [
            "* OK [ɐɐɐ] [UIDVALIDITY 12345] valid",
            "* OK [ɐɐɐ] [HIGHESTMODSEQ 98765] CONDSTORE",
        ])
        #expect(result.uidValidity == 12345)
        #expect(result.highestModSeq == 98765)
    }

    // MARK: - CONDSTORE changed-entry flag parsing

    @Test("changed entry: parses UID and flags")
    func changedEntryParsesFlags() {
        let entry = IMAPSessionClient.parseChangedMessageEntry(
            from: "* 5 FETCH (UID 7 FLAGS (\\Seen \\Draft))"
        )
        #expect(entry?.uid == 7)
        #expect(entry?.flags == ["\\Seen", "\\Draft"])
    }

    // Regression for the confirmed delta-sync crash: server-controlled non-ASCII
    // (here an X-GM-LABELS atom) before FLAGS used to crash `parseRawFlags`.
    @Test("changed entry: non-ASCII label before FLAGS does not crash")
    func changedEntryNonASCIIBeforeFlags() {
        let entry = IMAPSessionClient.parseChangedMessageEntry(
            from: "* 5 FETCH (UID 7 X-GM-LABELS (ɐɐɐ) FLAGS (\\Seen \\Draft))"
        )
        #expect(entry?.uid == 7)
        #expect(entry?.flags == ["\\Seen", "\\Draft"])
    }

    // MARK: - IMAPLineBuffer

    @Test("line buffer: empty buffer returns nil")
    func lineBufferEmpty() {
        var buffer = IMAPLineBuffer()
        #expect(buffer.takeLine() == nil)
    }

    @Test("line buffer: single line with CRLF")
    func lineBufferSingleLine() {
        var buffer = IMAPLineBuffer()
        buffer.append(Data("HELLO\r\n".utf8))
        #expect(buffer.takeLine() == "HELLO")
    }

    @Test("line buffer: single line with LF only")
    func lineBufferSingleLineLF() {
        var buffer = IMAPLineBuffer()
        buffer.append(Data("HELLO\n".utf8))
        #expect(buffer.takeLine() == "HELLO")
    }

    @Test("line buffer: multiple lines taken one at a time")
    func lineBufferMultipleLines() {
        var buffer = IMAPLineBuffer()
        buffer.append(Data("A\r\nB\r\nC\r\n".utf8))
        #expect(buffer.takeLine() == "A")
        #expect(buffer.takeLine() == "B")
        #expect(buffer.takeLine() == "C")
        #expect(buffer.takeLine() == nil)
    }

    @Test("line buffer: partial line at end returns nil until more data")
    func lineBufferPartialLine() {
        var buffer = IMAPLineBuffer()
        buffer.append(Data("HELLO".utf8))
        #expect(buffer.takeLine() == nil)
        buffer.append(Data("\r\n".utf8))
        #expect(buffer.takeLine() == "HELLO")
    }

    @Test("line buffer: bare CR does not terminate line")
    func lineBufferBareCR() {
        var buffer = IMAPLineBuffer()
        buffer.append(Data("HELLO\rWORLD\r\n".utf8))
        #expect(buffer.takeLine() == "HELLO\rWORLD")
    }

    @Test("line buffer: takeData with max length")
    func lineBufferTakeData() {
        var buffer = IMAPLineBuffer()
        buffer.append(Data("hello\r\nworld\r\n".utf8))
        let data = buffer.takeData(maxLength: 5)
        #expect(data != nil)
        #expect(String(data: data!, encoding: .utf8) == "hello")
    }

    @Test("line buffer: takeData with max length 0 returns nil")
    func lineBufferTakeDataZero() {
        var buffer = IMAPLineBuffer()
        buffer.append(Data("data".utf8))
        #expect(buffer.takeData(maxLength: 0) == nil)
    }

    // MARK: - IMAPMailboxNameCodec

    @Test("mailbox name codec: decodes escaped ampersand")
    func codecEscapedAmpersand() {
        let result = IMAPMailboxNameCodec.decode("Sent &- Archive")
        #expect(result == "Sent & Archive")
    }

    @Test("mailbox name codec: decodes imap-utf-7 folder name")
    func codecImapUtf7() {
        let result = IMAPMailboxNameCodec.decode("&A7w-&AMk-&AW0-")
        #expect(result == "μÉŭ")
    }

    @Test("mailbox name codec: encodes ASCII-only unchanged")
    func codecEncodesAsciiUnchanged() {
        let result = IMAPMailboxNameCodec.encode("INBOX")
        #expect(result == "INBOX")
    }

    @Test("mailbox name codec: encodes ampersand")
    func codecEncodesAmpersand() {
        let result = IMAPMailboxNameCodec.encode("A & B")
        #expect(result == "A &- B")
    }

    @Test("mailbox name codec: decodes trailing ampersand with no dash")
    func codecTrailingAmpersand() {
        let result = IMAPMailboxNameCodec.decode("Hello&")
        #expect(result == "Hello&")
    }

    @Test("mailbox name codec: decodes escaped ampersand sequence")
    func codecEscapedAmpersandSequence() {
        let result = IMAPMailboxNameCodec.decode("&-")
        #expect(result == "&")
    }

    @Test("mailbox name codec: encodes non-ASCII characters")
    func codecEncodesNonASCII() {
        let encoded = IMAPMailboxNameCodec.encode("ありが")
        #expect(encoded == "&MEIwijBM-")
    }

    // MARK: - IMAPSelectedMailbox (parse returns non-optional)

    @Test("selected mailbox: missing closing bracket for UIDVALIDITY")
    func selectedMailboxMissingBracket() {
        let result = IMAPSelectedMailbox.parse(from: ["* OK [UIDVALIDITY 42 SELECT completed"])
        #expect(result.uidValidity == nil)
    }

    @Test("selected mailbox: missing closing bracket for HIGHESTMODSEQ")
    func selectedMailboxMissingModSeqBracket() {
        let result = IMAPSelectedMailbox.parse(from: ["* OK [UIDVALIDITY 1] [HIGHESTMODSEQ 100 SELECT completed"])
        #expect(result.highestModSeq == nil)
    }

    @Test("selected mailbox: non-numeric UIDVALIDITY returns nil")
    func selectedMailboxNonNumericUidValidity() {
        let result = IMAPSelectedMailbox.parse(from: ["* OK [UIDVALIDITY abc]"])
        #expect(result.uidValidity == nil)
    }

    @Test("selected mailbox: non-numeric HIGHESTMODSEQ returns nil")
    func selectedMailboxNonNumericModSeq() {
        let result = IMAPSelectedMailbox.parse(from: ["* OK [UIDVALIDITY 1] [HIGHESTMODSEQ abc]"])
        #expect(result.highestModSeq == nil)
    }

    // MARK: - IMAPIdleEvent

    @Test("idle event: fewer than 3 parts returns nil")
    func idleEventTooFewParts() {
        let result = IMAPIdleEvent.parse("HELLO")
        #expect(result == nil)
    }

    @Test("idle event: non-numeric sequence number returns nil")
    func idleEventNonNumericSeq() {
        let result = IMAPIdleEvent.parse("* ABC EXISTS")
        #expect(result == nil)
    }

    @Test("idle event: zero EXISTS count")
    func idleEventZeroExists() {
        let result = IMAPIdleEvent.parse("* 0 EXISTS")
        #expect(result != nil)
        if case .exists(let count) = result! {
            #expect(count == 0)
        } else {
            Issue.record("expected exists")
        }
    }

    @Test("idle event: FETCH without FLAGS returns nil")
    func idleEventFetchWithoutFlags() {
        let result = IMAPIdleEvent.parse("* 1 FETCH (UID 100)")
        #expect(result == nil)
    }

    @Test("idle event: EXPUNGE with zero count")
    func idleEventExpungeZero() {
        let result = IMAPIdleEvent.parse("* 0 EXPUNGE")
        #expect(result != nil)
        if case .expunged(sequenceNumber: let seq) = result! {
            #expect(seq == 0)
        } else {
            Issue.record("expected expunged")
        }
    }

    // MARK: - IMAPFolderListing

    @Test("folder listing: NIL delimiter returns empty string")
    func folderListingNilDelimiter() {
        let result = IMAPFolderListing.parse("* LIST (\\HasNoChildren) NIL \"INBOX\"")
        #expect(result != nil)
        #expect(result?.delimiter == "")
    }

    @Test("folder listing: missing LIST marker returns nil")
    func folderListingMissingList() {
        let result = IMAPFolderListing.parse("* \\HasNoChildren \"/\" \"INBOX\"")
        #expect(result == nil)
    }

    @Test("folder listing: missing opening paren for flags returns nil")
    func folderListingMissingOpenParen() {
        let result = IMAPFolderListing.parse("* LIST \\HasNoChildren) \"/\" \"INBOX\"")
        #expect(result == nil)
    }

    @Test("folder listing: unquoted mailbox name")
    func folderListingUnquotedName() {
        let result = IMAPFolderListing.parse("* LIST (\\HasNoChildren) \"/\" INBOX")
        #expect(result != nil)
        #expect(result?.path == "INBOX")
    }

    @Test("folder listing: role detection for Drafts, Trash, Spam, Archive")
    func folderListingRoles() {
        let drafts = IMAPFolderListing.parse("* LIST (\\Drafts) \"/\" \"Drafts\"")
        #expect(drafts?.role == .drafts)

        let trash = IMAPFolderListing.parse("* LIST (\\Trash) \"/\" \"Trash\"")
        #expect(trash?.role == .trash)

        let spam = IMAPFolderListing.parse("* LIST (\\Junk) \"/\" \"Spam\"")
        #expect(spam?.role == .spam)

        let archive = IMAPFolderListing.parse("* LIST (\\Archive) \"/\" \"Archive\"")
        #expect(archive?.role == .archive)
    }

    // MARK: - IMAPMessageListing

    @Test("message listing: NO FLAGS attribute returns nil")
    func messageListingNoFlags() {
        let result = IMAPMessageListing.parse("* 1 FETCH (UID 100)")
        #expect(result == nil)
    }

    @Test("message listing: empty flags list")
    func messageListingEmptyFlags() {
        let result = IMAPMessageListing.parse(
            "* 1 FETCH (FLAGS () UID 100 ENVELOPE (\"Date\" \"Subj\" NIL NIL NIL NIL NIL NIL NIL NIL))"
        )
        #expect(result != nil)
        #expect(result?.isRead == false)
        #expect(result?.isFlagged == false)
        #expect(result?.isAnswered == false)
    }

    @Test("message listing: ENVELOPE with fewer than 10 elements returns nil")
    func messageListingShortEnvelope() {
        let result = IMAPMessageListing.parse(
            "* 1 FETCH (FLAGS (\\Seen) UID 100 ENVELOPE (\"Date\" \"Subject\" (\"From\" NIL NIL \"from\" \"domain.com\")))"
        )
        #expect(result == nil)
    }

    @Test("message listing: invalid date returns distantPast")
    func messageListingInvalidDate() {
        let result = IMAPMessageListing.parse(
            "* 1 FETCH (FLAGS (\\Seen) UID 100 ENVELOPE (\"NotADate\" \"Subj\" NIL NIL NIL NIL NIL NIL NIL NIL))"
        )
        #expect(result != nil)
        #expect(result?.date == Date.distantPast)
    }

    @Test("message listing: date with trailing timezone comment")
    func messageListingDateWithTrailingTimezoneComment() throws {
        let result = IMAPMessageListing.parse(
            "* 1 FETCH (FLAGS (\\Seen) UID 100 ENVELOPE (\"Mon, 8 Jun 2026 08:51:02 +0000 (UTC)\" \"Subj\" NIL NIL NIL NIL NIL NIL NIL NIL))"
        )

        let calendar = Calendar(identifier: .gregorian)
        let expected = try #require(calendar.date(from: DateComponents(
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 6,
            day: 8,
            hour: 8,
            minute: 51,
            second: 2
        )))
        #expect(result?.date == expected)
    }

    @Test("message listing: zone-less date is parsed as UTC, not dropped to distantPast")
    func messageListingDateWithoutTimezone() throws {
        // Malformed (no zone) but seen in the wild; previously fell through to
        // Date.distantPast, hiding the real date.
        let result = IMAPMessageListing.parse(
            "* 1 FETCH (FLAGS (\\Seen) UID 100 ENVELOPE (\"Mon, 8 Jun 2026 08:51:02\" \"Subj\" NIL NIL NIL NIL NIL NIL NIL NIL))"
        )

        let calendar = Calendar(identifier: .gregorian)
        let expected = try #require(calendar.date(from: DateComponents(
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 6,
            day: 8,
            hour: 8,
            minute: 51,
            second: 2
        )))
        #expect(result?.date == expected)
    }

    @Test("message listing: zoned date is unaffected by the zone-less fallback")
    func messageListingZonedDateUnaffectedByFallback() throws {
        // Guards the ordering: a +0200 date must keep its offset and not be
        // mis-read as UTC by the new zone-less formats.
        let result = IMAPMessageListing.parse(
            "* 1 FETCH (FLAGS (\\Seen) UID 100 ENVELOPE (\"Mon, 8 Jun 2026 10:51:02 +0200\" \"Subj\" NIL NIL NIL NIL NIL NIL NIL NIL))"
        )

        let calendar = Calendar(identifier: .gregorian)
        let expected = try #require(calendar.date(from: DateComponents(
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 6,
            day: 8,
            hour: 8, // 10:51 +0200 == 08:51 UTC
            minute: 51,
            second: 2
        )))
        #expect(result?.date == expected)
    }

    @Test("message listing: multiple UID attributes uses first")
    func messageListingMultipleUIDs() {
        let result = IMAPMessageListing.parse(
            "* 1 FETCH (FLAGS (\\Seen) UID 100 UID 200 ENVELOPE (\"Date\" \"Subj\" NIL NIL NIL NIL NIL NIL NIL NIL))"
        )
        #expect(result?.uid == 100)
    }

    @Test("message listing: FLAGS adjacent to paren without space")
    func messageListingFlagsAdjacentParen() {
        let result = IMAPMessageListing.parse(
            "* 1 FETCH (FLAGS (\\Seen) UID 42 ENVELOPE (\"Date\" \"Subj\" NIL NIL NIL NIL NIL NIL NIL NIL))"
        )
        #expect(result != nil)
        #expect(result?.uid == 42)
        #expect(result?.isRead == true)
    }

    // MARK: - IMAPMessageSource

    @Test("message source: no fetch lines returns nil")
    func messageSourceNoFetchLines() {
        let result = IMAPMessageSource.parse(["* SEARCH 1", "A0002 OK SEARCH completed"], uid: 1)
        #expect(result == nil)
    }

    @Test("message source: matching UID collects trailing lines")
    func messageSourceTrailingLines() {
        let result = IMAPMessageSource.parse(
            ["* 1 FETCH (UID 1 BODY[] {0}", ")", "A0003 OK FETCH completed"],
            uid: 1
        )
        #expect(result != nil)
        #expect(result?.rawMessage == ")\nA0003 OK FETCH completed")
    }

    @Test("literal: a normal byte count parses")
    func literalNormalByteCount() {
        let literal = IMAPSessionClient.trailingLiteral(in: "A1 OK ready {100}")
        #expect(literal?.byteCount == 100)
    }

    @Test("literal: a non-synchronizing literal {N+} parses")
    func literalNonSynchronizing() {
        let literal = IMAPSessionClient.trailingLiteral(in: "+ go {2048+}")
        #expect(literal?.byteCount == 2048)
    }

    @Test("literal: the maximum byte count is accepted, one over is rejected")
    func literalByteCountBoundary() {
        let atMax = IMAPSessionClient.trailingLiteral(in: "x {\(IMAPSessionClient.maxLiteralByteCount)}")
        #expect(atMax?.byteCount == IMAPSessionClient.maxLiteralByteCount)

        let overMax = IMAPSessionClient.trailingLiteral(in: "x {\(IMAPSessionClient.maxLiteralByteCount + 1)}")
        #expect(overMax == nil)
    }

    @Test("literal: an absurd byte count is rejected so the read can't exhaust memory")
    func literalAbsurdByteCountRejected() {
        // A hostile/buggy server could announce a huge literal and then stream
        // data; the parser must refuse it rather than buffer gigabytes.
        #expect(IMAPSessionClient.trailingLiteral(in: "* 1 FETCH (BODY[] {999999999999}") == nil)
    }

    @Test("line buffer tracks pending bytes so the reader can bound a terminator-less stream")
    func lineBufferTracksPendingBytes() {
        // The transport's readLine throws once pendingByteCount exceeds
        // MailTransportLimits.maxLineByteCount; this verifies the count it reads.
        var buffer = IMAPLineBuffer()
        buffer.append(Data(count: 5000)) // no CRLF yet
        #expect(buffer.pendingByteCount == 5000)
        #expect(buffer.takeLine() == nil) // nothing to take without a terminator
        #expect(buffer.pendingByteCount == 5000) // still buffered

        buffer.append(Data("\r\nrest".utf8))
        #expect(buffer.takeLine() != nil) // consumes through the CRLF
        #expect(buffer.pendingByteCount == 4) // "rest" remains
    }
}
