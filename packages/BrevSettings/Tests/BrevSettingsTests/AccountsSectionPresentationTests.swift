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

@Suite("AccountsSectionPresentation")
struct AccountsSectionPresentationTests {
    @Test("add account action shows pending state while adding")
    func addAccountActionShowsPendingState() {
        #expect(AccountsSectionPresentation.addAccountAction(
            isAddingAccount: false,
            signingOutAccountIDs: []
        ) == AccountsSectionActionPresentation(title: "Add account", isDisabled: false))

        #expect(AccountsSectionPresentation.addAccountAction(
            isAddingAccount: true,
            signingOutAccountIDs: []
        ) == AccountsSectionActionPresentation(title: "Adding…", isDisabled: true))
    }

    @Test("add account action is disabled while sign-out is pending")
    func addAccountActionIsDisabledWhileSignOutIsPending() {
        #expect(AccountsSectionPresentation.addAccountAction(
            isAddingAccount: false,
            signingOutAccountIDs: ["a"]
        ) == AccountsSectionActionPresentation(title: "Add account", isDisabled: true))
    }

    @Test("add account action hides when account setup is unavailable")
    func addAccountActionHidesWhenAccountSetupIsUnavailable() {
        #expect(AccountsSectionPresentation.showsAddAccountAction(isAddAccountAvailable: true))
        #expect(!AccountsSectionPresentation.showsAddAccountAction(isAddAccountAvailable: false))
    }

    @Test("sign-out action shows pending state for the active row")
    func signOutActionShowsPendingStateForActiveRow() {
        #expect(AccountsSectionPresentation.signOutAction(
            accountID: "a",
            isAddingAccount: false,
            signingOutAccountIDs: ["a"]
        ) == AccountsSectionActionPresentation(title: "Signing out…", isDisabled: true))
    }

    @Test("sign-out action is disabled while another account operation is pending")
    func signOutActionIsDisabledWhileAnotherAccountOperationIsPending() {
        #expect(AccountsSectionPresentation.signOutAction(
            accountID: "a",
            isAddingAccount: true,
            signingOutAccountIDs: []
        ) == AccountsSectionActionPresentation(title: "Sign out", isDisabled: true))

        #expect(AccountsSectionPresentation.signOutAction(
            accountID: "a",
            isAddingAccount: false,
            signingOutAccountIDs: ["b"]
        ) == AccountsSectionActionPresentation(title: "Sign out", isDisabled: true))
    }

    @Test("set-default action reflects the current account")
    func setDefaultActionReflectsCurrentAccount() {
        #expect(AccountsSectionPresentation.setDefaultAction(
            accountID: "a",
            currentAccountID: "a",
            isAddingAccount: false,
            signingOutAccountIDs: []
        ) == AccountsSectionActionPresentation(title: "Default", isDisabled: true))

        #expect(AccountsSectionPresentation.setDefaultAction(
            accountID: "b",
            currentAccountID: "a",
            isAddingAccount: false,
            signingOutAccountIDs: []
        ) == AccountsSectionActionPresentation(title: "Set default", isDisabled: false))
    }

    @Test("account mutation actions are disabled while another operation is pending")
    func accountMutationActionsDisableWhileBusy() {
        #expect(AccountsSectionPresentation.setDefaultAction(
            accountID: "a",
            currentAccountID: "b",
            isAddingAccount: true,
            signingOutAccountIDs: []
        ) == AccountsSectionActionPresentation(title: "Set default", isDisabled: true))

        #expect(AccountsSectionPresentation.removeAction(
            isAddingAccount: false,
            signingOutAccountIDs: ["b"]
        ) == AccountsSectionActionPresentation(title: "Remove", isDisabled: true))
    }
}

@Suite("AccountMailboxSelectionPresentation")
struct AccountMailboxSelectionPresentationTests {
    private let first = MailSourceID(accountID: "acct-1", mailboxID: "first")
    private let second = MailSourceID(accountID: "acct-1", mailboxID: "second")

    @Test("empty preferences enable all mailboxes and choose first default")
    func emptyPreferencesEnableAllMailboxes() {
        let presentation = AccountMailboxSelectionPresentation.row(
            sourceID: first,
            availableSourceIDs: [first, second],
            preferences: .defaults
        )

        #expect(presentation == AccountMailboxRowPresentation(
            isEnabled: true,
            canToggle: true,
            isDefault: true,
            defaultActionTitle: "Default",
            isDefaultActionDisabled: true
        ))
    }

    @Test("last enabled mailbox cannot be toggled off")
    func lastEnabledMailboxCannotBeToggledOff() {
        let presentation = AccountMailboxSelectionPresentation.row(
            sourceID: first,
            availableSourceIDs: [first, second],
            preferences: MailboxSourcePreferences(
                enabledSourceIDs: [first],
                defaultSourceID: first
            )
        )

        #expect(presentation.canToggle == false)
        #expect(presentation.isDefault)
    }

    @Test("disabled mailbox can be re-enabled but not made default")
    func disabledMailboxCanBeReenabledButNotDefaulted() {
        let presentation = AccountMailboxSelectionPresentation.row(
            sourceID: second,
            availableSourceIDs: [first, second],
            preferences: MailboxSourcePreferences(
                enabledSourceIDs: [first],
                defaultSourceID: first
            )
        )

        #expect(presentation.isEnabled == false)
        #expect(presentation.canToggle)
        #expect(presentation.isDefaultActionDisabled)
    }
}

@Suite("ConflictReviewPresentation")
struct ConflictReviewPresentationTests {
    @Test("zero conflicts → button hidden (title is nil)")
    func zeroConflictsHidesButton() {
        #expect(ConflictReviewPresentation.reviewButtonTitle(conflictCount: 0) == nil)
    }

    @Test("one conflict → singular title")
    func oneConflictSingularTitle() {
        #expect(ConflictReviewPresentation.reviewButtonTitle(conflictCount: 1) == "Review 1 conflict")
    }

    @Test("multiple conflicts → plural title")
    func multipleConflictsPluralTitle() {
        #expect(ConflictReviewPresentation.reviewButtonTitle(conflictCount: 3) == "Review 3 conflicts")
    }

    @Test("large count formats correctly")
    func largeCountFormatsCorrectly() {
        #expect(ConflictReviewPresentation.reviewButtonTitle(conflictCount: 100) == "Review 100 conflicts")
    }
}

@Suite("AccountRowLayoutPolicy")
struct AccountRowLayoutPolicyTests {
    @Test("iOS always uses the compact account row")
    func iOSAlwaysUsesCompactAccountRow() {
        #expect(AccountRowLayoutPolicy.layout(
            for: .compact,
            platform: .iOS
        ) == .compact)
        #expect(AccountRowLayoutPolicy.layout(
            for: .regular,
            platform: .iOS
        ) == .compact)
        #expect(AccountRowLayoutPolicy.layout(
            for: nil,
            platform: .iOS
        ) == .compact)
    }

    @Test("macOS uses horizontal rows unless the size class is compact")
    func macOSUsesHorizontalRowsUnlessSizeClassIsCompact() {
        #expect(AccountRowLayoutPolicy.layout(
            for: .regular,
            platform: .macOS
        ) == .horizontal)
        #expect(AccountRowLayoutPolicy.layout(
            for: nil,
            platform: .macOS
        ) == .horizontal)
        #expect(AccountRowLayoutPolicy.layout(
            for: .compact,
            platform: .macOS
        ) == .compact)
    }
}
