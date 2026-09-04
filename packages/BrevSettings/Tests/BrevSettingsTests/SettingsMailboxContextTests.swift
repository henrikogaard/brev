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

@Suite("Settings mailbox context")
struct SettingsMailboxContextTests {
    @Test("Settings follows Mail source changes and retains manual scope during folder refresh")
    func selectionFollowsSource() {
        let work = MailSourceID(accountID: "account", mailboxID: "work")
        let personal = MailSourceID(accountID: "account", mailboxID: "personal")
        let old = SettingsMailboxContext(selectedSourceID: work)
        let next = SettingsMailboxContext(selectedSourceID: personal)
        #expect(next.selection(replacing: old, current: work) == personal)
        #expect(old.selection(replacing: old, current: personal) == personal)
    }
}
