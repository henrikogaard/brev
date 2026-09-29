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

@Suite("Mobile mailbox favorites")
struct MailboxFavoritesTests {
    private func section(_ id: String) -> MailSourceSection {
        MailSourceSection(id: MailSourceID(accountID: "account", mailboxID: id),
                          account: BrevAccount(id: "account", displayName: "User", emailAddress: "me@example.org"),
                          mailbox: Mailbox(id: id, email: "\(id)@example.org", displayName: id),
                          folders: [Folder(id: "inbox", name: "INBOX", role: .inbox, unreadCount: 3, totalCount: 30),
                                    Folder(id: "drafts", name: "Drafts", role: .drafts, unreadCount: 0, totalCount: 2),
                                    Folder(id: "sent", name: "Sent", role: .sent)])
    }

    @Test("first use offers all inboxes and each source inbox without duplicate source identities")
    func defaultsAndCounts() {
        let candidates = MailboxFavorite.candidates(sections: [section("private"), section("work")])
        let visible = MailboxFavorites(data: Data()).ordered(candidates, visibleOnly: true)
        #expect(visible.map(\.title) == ["All Inboxes", "private", "work"])
        #expect(Set(candidates.map(\.id)).count == 7)
        #expect(visible.first?.count == 6)
        #expect(visible.first?.countDescription == "6 unread")
        #expect(candidates.first { $0.title == "Drafts" }?.count == 2)
        #expect(candidates.first { $0.title == "Drafts" }?.countDescription == "2 drafts")
    }

    @Test("editing persists order and visibility without losing filtered account preferences")
    func preferencesSurviveProfiles() throws {
        let candidates = MailboxFavorite.candidates(sections: [section("private"), section("work")])
        let workInbox = candidates[2]
        let privateDrafts = candidates[3]
        var settings = MailboxFavorites(data: Data())
        settings.setVisible(false, id: .allInboxes)
        settings.setVisible(true, id: privateDrafts.id)
        settings.reorder([privateDrafts.id, workInbox.id, candidates[1].id])
        let restored = MailboxFavorites(data: settings.data)
        #expect(restored.ordered(candidates, visibleOnly: true).map(\.id)
            == [privateDrafts.id, workInbox.id, candidates[1].id])
        let privateOnly = MailboxFavorite.candidates(sections: [section("private")])
        #expect(restored.ordered(privateOnly, visibleOnly: true).map(\.id) == [privateDrafts.id, candidates[1].id])
        #expect(restored == settings)
    }

    @Test("bad storage falls back and unavailable folders never produce destinations")
    func unavailableDestinations() {
        #expect(MailboxFavorite.candidates(sections: []).isEmpty)
        let candidates = MailboxFavorite.candidates(sections: [section("private")])
        #expect(MailboxFavorites(data: Data("bad".utf8)).ordered(candidates, visibleOnly: true).count == 2)
    }
}
