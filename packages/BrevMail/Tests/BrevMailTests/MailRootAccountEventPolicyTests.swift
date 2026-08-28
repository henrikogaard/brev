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
import Testing

@Suite("MailRootAccountEventPolicy")
struct MailRootAccountEventPolicyTests {
    @Test("current account disconnect signs out when a sign-out handler exists")
    func currentAccountDisconnectSignsOutWhenHandlerExists() {
        #expect(MailRootAccountEventPolicy.action(
            for: .accountDisconnected(accountID: "account-1"),
            currentAccountID: "account-1",
            hasSignOutHandler: true
        ) == .signOut)
    }

    @Test("non-disconnect and stale account events are ignored")
    func nonDisconnectAndStaleAccountEventsAreIgnored() {
        #expect(MailRootAccountEventPolicy.action(
            for: .accountConnected(accountID: "account-1"),
            currentAccountID: "account-1",
            hasSignOutHandler: true
        ) == .ignore)
        #expect(MailRootAccountEventPolicy.action(
            for: .accountDisconnected(accountID: "account-2"),
            currentAccountID: "account-1",
            hasSignOutHandler: true
        ) == .ignore)
    }

    @Test("disconnect without a sign-out handler is ignored")
    func disconnectWithoutSignOutHandlerIsIgnored() {
        #expect(MailRootAccountEventPolicy.action(
            for: .accountDisconnected(accountID: "account-1"),
            currentAccountID: "account-1",
            hasSignOutHandler: false
        ) == .ignore)
    }

    @Test("background message events still notify and refresh badge state")
    func backgroundMessageEventsStillNotifyAndRefreshBadgeState() {
        let effects = MailRootAccountEventPolicy.mailboxEventEffects(
            for: .messagesAdded(folderID: "inbox", messageIDs: ["message-1"]),
            eventAccountID: "account-2",
            selectedAccountID: "account-1"
        )

        #expect(effects.refreshVisibleContent == false)
        #expect(effects.refreshBackgroundAccountState == true)
        #expect(effects.postNewMailNotification == true)
    }

    @Test("background folder refreshes refresh badge state without a notification")
    func backgroundFolderRefreshesRefreshBadgeStateWithoutNotification() {
        let effects = MailRootAccountEventPolicy.mailboxEventEffects(
            for: .folderRefreshed(folderID: "inbox"),
            eventAccountID: "account-2",
            selectedAccountID: "account-1"
        )

        #expect(effects.refreshVisibleContent == false)
        #expect(effects.refreshBackgroundAccountState == true)
        #expect(effects.postNewMailNotification == false)
    }

    @Test("selected message events retain visible refresh behavior")
    func selectedMessageEventsRetainVisibleRefreshBehavior() {
        let effects = MailRootAccountEventPolicy.mailboxEventEffects(
            for: .messagesAdded(folderID: "inbox", messageIDs: ["message-1"]),
            eventAccountID: "account-1",
            selectedAccountID: "account-1"
        )

        #expect(effects.refreshVisibleContent == true)
        #expect(effects.refreshBackgroundAccountState == false)
        #expect(effects.postNewMailNotification == true)
    }
}
