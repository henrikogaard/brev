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
@testable import BrevSettings
import Testing

@Suite("AccountDetailPresentation")
struct AccountDetailPresentationTests {
    private let work = Mailbox(id: "work", email: "work@example.org", displayName: "Work", isPrimary: true)
    private let home = Mailbox(id: "home", email: "home@example.org", displayName: "Home")
    private let bare = Mailbox(id: "bare", email: "bare@example.org", displayName: "")

    private func sourceIDs(_ mailboxes: [Mailbox]) -> [MailSourceID] {
        mailboxes.map { MailSourceID(accountID: "acct", mailboxID: $0.id) }
    }

    @Test("default mailbox choices list only enabled mailboxes and mark the default with a checkmark")
    func defaultChoicesListEnabledMailboxes() {
        let mailboxes = [work, home]
        let available = sourceIDs(mailboxes)
        let preferences = MailboxSourcePreferences(
            enabledSourceIDs: [available[0], available[1]],
            defaultSourceID: available[1]
        )
        let choices = AccountMailboxSelectionPresentation.defaultChoices(
            accountID: "acct",
            mailboxes: mailboxes,
            availableSourceIDs: available,
            preferences: preferences
        )
        #expect(choices.map(\.mailboxID) == ["work", "home"])
        #expect(choices.map(\.isSelected) == [false, true])
    }

    @Test("a disabled mailbox cannot be the default and is not offered")
    func disabledMailboxIsNotOffered() {
        let mailboxes = [work, home]
        let available = sourceIDs(mailboxes)
        let preferences = MailboxSourcePreferences(
            enabledSourceIDs: [available[0]],
            defaultSourceID: available[0]
        )
        let choices = AccountMailboxSelectionPresentation.defaultChoices(
            accountID: "acct",
            mailboxes: mailboxes,
            availableSourceIDs: available,
            preferences: preferences
        )
        #expect(choices.map(\.mailboxID) == ["work"])
        #expect(choices.first?.isSelected == true)
    }

    @Test("choices show the display name first and fall back to the address")
    func choiceTitlesPreferDisplayName() {
        let mailboxes = [work, bare]
        let available = sourceIDs(mailboxes)
        let choices = AccountMailboxSelectionPresentation.defaultChoices(
            accountID: "acct",
            mailboxes: mailboxes,
            availableSourceIDs: available,
            preferences: MailboxSourcePreferences(enabledSourceIDs: available, defaultSourceID: available[0])
        )
        #expect(choices.map(\.title) == ["Work", "bare@example.org"])
    }

    @Test("account titles show the display name first and fall back to the address")
    func accountTitleFallsBackToAddress() {
        let named = BrevAccount(id: "a", displayName: "Henrik", emailAddress: "henrik@example.org")
        let unnamed = BrevAccount(id: "b", displayName: "", emailAddress: "b@example.org")
        #expect(AccountsSectionPresentation.title(for: named) == "Henrik")
        #expect(AccountsSectionPresentation.title(for: unnamed) == "b@example.org")
    }

    @Test("mailbox switches are offered for several mailboxes, while loading, or after a load error")
    func mailboxControlsVisibility() {
        #expect(AccountsSectionPresentation.showsMailboxControls(mailboxCount: 2, isLoading: false, hasError: false))
        #expect(AccountsSectionPresentation.showsMailboxControls(mailboxCount: 0, isLoading: true, hasError: false))
        #expect(AccountsSectionPresentation.showsMailboxControls(mailboxCount: 1, isLoading: false, hasError: true))
        #expect(!AccountsSectionPresentation.showsMailboxControls(mailboxCount: 1, isLoading: false, hasError: false))
    }
}
