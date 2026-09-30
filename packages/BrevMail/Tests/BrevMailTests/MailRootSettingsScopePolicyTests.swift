/*
 Brev - Mail Client for macOS and iOS
 Copyright (c) 2026 Brev contributors

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included
 in all copies or substantial portions of the Software.
 */

import BrevBackend
@testable import BrevMail
import Testing

@Suite("MailRootSettingsScopePolicy")
struct MailRootSettingsScopePolicyTests {
    private let work = MailSourceID(accountID: "account", mailboxID: "work")
    private let personal = MailSourceID(accountID: "account", mailboxID: "personal")

    @Test("an explicit Mail selection wins over the default section")
    func explicitSelectionWins() {
        #expect(
            MailRootSettingsScopePolicy.effectiveSourceID(
                selectedSourceID: work,
                defaultSectionID: personal
            ) == work
        )
    }

    @Test("falls back to the default section when Mail has no explicit selection")
    func fallsBackToDefaultSection() {
        // The empty Folder Sync scope: with the mailbox list visible Mail's
        // selected source is nil while the window still shows the default
        // section, so Settings must resolve the same effective source instead
        // of publishing an empty scope.
        #expect(
            MailRootSettingsScopePolicy.effectiveSourceID(
                selectedSourceID: nil,
                defaultSectionID: work
            ) == work
        )
    }

    @Test("stays empty with no accounts so the zero-account state remains")
    func staysEmptyWithoutAccounts() {
        #expect(
            MailRootSettingsScopePolicy.effectiveSourceID(
                selectedSourceID: nil,
                defaultSectionID: nil
            ) == nil
        )
    }
}
