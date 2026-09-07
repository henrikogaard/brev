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

@Suite("Source-owned conversation membership")
struct ConversationMembershipTests {
    let source = MailSourceID(accountID: "a", mailboxID: "a")

    @Test("identifier parsing preserves case, removes nested comments and rejects malformed fields")
    func identifierParsingIsConservative() throws {
        #expect(try ConversationMembershipResolver.identifiers(in: " <A>\r\n <a> (nested (<ignored>)) ") == ["A", "a"])
        #expect(throws: ConversationLookupError.self) { try ConversationMembershipResolver.identifiers(in: "<unfinished") }
        #expect(throws: ConversationLookupError.self) {
            try ConversationMembershipResolver.identifiers(in: "first(comment)second")
        }
        #expect(throws: ConversationLookupError.self) { try ConversationMembershipResolver.identifiers(in: String(
            repeating: "a",
            count: 65537
        )) }
    }

    @Test("identifier parsing rejects embedded controls that SQLite text binding would truncate")
    func controlsCannotCreateLinks() {
        for value in ["<abc\u{0000}def>", "abc\u{0001}def", "<abc\u{007f}def>"] {
            #expect(throws: ConversationLookupError.self) { try ConversationMembershipResolver.identifiers(in: value) }
        }
    }

    @Test("empty source and folder locators cannot form a usable snapshot")
    func emptyLocatorsAreRejected() {
        for (sourceID, folderID) in [(source, ""), (MailSourceID(accountID: "", mailboxID: ""), "Inbox")] {
            let header = MessageHeader(id: "1", threadID: "1", folderID: folderID,
                                       from: Correspondent(email: "a@example.org"), to: [], subject: "", snippet: "",
                                       date: Date())
            let invalid = ConversationMember(sourceID: sourceID, header: header)
            #expect(throws: ConversationLookupError.self) {
                try ConversationSnapshot(anchor: invalid.location, members: [invalid], coverage: .cached)
            }
        }
    }

    @Test("comment text is not a reply link")
    func commentsDoNotCreateLinks() throws {
        let root = member("I:1", folder: "I", messageID: "<root>")
        let unrelated = member("I:2", folder: "I", messageID: "<unrelated>")
        let reply = member("S:3", folder: "S", messageID: "<reply>", parent: "<root> (ignore <unrelated>)")
        let result = try ConversationMembershipResolver.cached(around: reply, candidates: [root, unrelated])
        #expect(Set(result.members.map { $0.header.id }) == ["I:1", "S:3"])
    }

    @Test("complete coverage rejects unavailable folders and contradictory folder generations")
    func snapshotRejectsFalseCompleteness() throws {
        let a = member("I:1", folder: "I", messageID: "<a>")
        #expect(throws: ConversationLookupError.self) {
            try ConversationSnapshot(
                anchor: a.location,
                members: [a],
                coverage: .completeForScope,
                unavailableFolderIDs: ["Sent"]
            )
        }
        let old = ConversationMember(sourceID: source, header: a.header, folderGeneration: 10)
        let changed = ConversationMember(sourceID: source, header: a.header, folderGeneration: 11)
        #expect(throws: ConversationLookupError.self) {
            try ConversationSnapshot(anchor: old.location, members: [old, changed], coverage: .cached)
        }
    }

    @Test("reply chains include Sent and Archive without merging equal subjects")
    func crossFolderLinks() throws {
        let root = member("Inbox:1", folder: "Inbox", messageID: "<root@example>")
        let reply = member("Sent:2", folder: "Sent", messageID: "<reply@example>", parent: "<root@example>")
        let older = member("Archive:3", folder: "Archive", messageID: "<older@example>", references: ["<root@example>"])
        let unrelated = member("Inbox:4", folder: "Inbox", messageID: "<other@example>")
        let snapshot = try ConversationMembershipResolver.cached(around: reply, candidates: [root, reply, older, unrelated])
        #expect(Set(snapshot.members.map { $0.header.id }) == ["Inbox:1", "Sent:2", "Archive:3"])
        #expect(snapshot.anchor == reply.location)
        #expect(snapshot.coverage == .cached)
    }

    @Test("absent parents and cycles link members without changing the selected anchor")
    func absentParentsAndCycles() throws {
        let a = member("I:1", folder: "I", messageID: "<a>", parent: "<missing>", references: ["<b>"])
        let b = member("S:2", folder: "S", messageID: "<b>", parent: "<missing>", references: ["<a>"])
        let result = try ConversationMembershipResolver.cached(around: a, candidates: [b])
        #expect(result.members.count == 2)
        #expect(result.anchor == a.location)
    }

    @Test("ambiguous reused identifiers cannot merge unrelated senders")
    func ambiguousIDsStaySeparate() throws {
        let a = member("I:1", folder: "I", messageID: "<reused>")
        let b = member("S:2", folder: "S", messageID: "<reused>", sender: "other@example.org")
        let reply = member("I:3", folder: "I", messageID: "<reply>", parent: "<reused>")
        let result = try ConversationMembershipResolver.cached(around: a, candidates: [b, reply])
        #expect(result.members.map { $0.header.id } == ["I:1"])
        #expect(result.ambiguousIdentifiers == ["reused"])
    }

    @Test("physical copies and equal raw IDs in different folders retain distinct locations")
    func copiesRetainLocations() throws {
        let a = member("1", folder: "Inbox", messageID: "<same>")
        let b = member("1", folder: "Archive", messageID: "<same>")
        let result = try ConversationMembershipResolver.cached(around: a, candidates: [b])
        #expect(result.members.count == 2)
        #expect(Set(result.members.map(\.location)).count == 2)
        #expect(result.ambiguousIdentifiers == ["same"])
    }

    @Test("foreign mailbox candidates are rejected")
    func rejectsForeignSource() throws {
        let a = member("I:1", folder: "I", messageID: "<a>")
        let foreign = ConversationMember(sourceID: MailSourceID(accountID: "b", mailboxID: "b"), header: a.header)
        #expect(throws: ConversationLookupError.self) {
            try ConversationMembershipResolver.cached(around: a, candidates: [foreign])
        }
    }

    private func member(_ id: String, folder: String, messageID: String, parent: String? = nil,
                        references: [String]? = nil, sender: String = "sender@example.org") -> ConversationMember {
        ConversationMember(sourceID: source, header: MessageHeader(id: id, threadID: id, folderID: folder,
                                                                   from: Correspondent(email: sender), to: [],
                                                                   subject: "Same subject",
                                                                   snippet: "", date: Date(timeIntervalSince1970: 100),
                                                                   messageID: messageID, inReplyTo: parent),
                           references: references)
    }
}
