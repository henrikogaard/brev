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
import Testing

/// The account-colour dot on list avatars (#306 slice 5).
@Suite("Message list account dot")
struct MessageListAccountDotTests {
    @Test("accounts take palette slots in sidebar order, so two accounts never share one")
    func sidebarOrder() {
        let accounts = ["work", "personal", "club"]
        #expect(MessageListAccountDot.paletteIndex(accountID: "work", orderedAccountIDs: accounts,
                                                   paletteCount: 8) == 0)
        #expect(MessageListAccountDot.paletteIndex(accountID: "personal", orderedAccountIDs: accounts,
                                                   paletteCount: 8) == 1)
        #expect(MessageListAccountDot.paletteIndex(accountID: "club", orderedAccountIDs: accounts,
                                                   paletteCount: 8) == 2)
    }

    @Test("more accounts than colours wrap around the palette")
    func wraps() {
        #expect(MessageListAccountDot.paletteIndex(accountID: "c", orderedAccountIDs: ["a", "b", "c"],
                                                   paletteCount: 2) == 0)
    }

    @Test("no dot for a single account, an unknown account or an empty palette")
    func noDot() {
        #expect(MessageListAccountDot.paletteIndex(accountID: "work", orderedAccountIDs: ["work"],
                                                   paletteCount: 8) == nil)
        #expect(MessageListAccountDot.paletteIndex(accountID: "other", orderedAccountIDs: ["work", "home"],
                                                   paletteCount: 8) == nil)
        #expect(MessageListAccountDot.paletteIndex(accountID: "work", orderedAccountIDs: ["work", "home"],
                                                   paletteCount: 0) == nil)
    }

    @Test("account order comes from the sources, each account once")
    func orderedAccounts() {
        #expect(MessageListAccountDot.orderedAccountIDs(["work", "work", "home", "work", "club"])
            == ["work", "home", "club"])
    }
}
