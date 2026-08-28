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

@Suite("Mailbox action toolbar placement")
struct MailRootMailboxActionToolbarPolicyTests {
    @Test("macOS puts Get Mail and New Message beside the reader actions")
    func macOSPlacesMailboxActionsInTheDetailSection() {
        #expect(MailRootMailboxActionToolbarPolicy.section(platform: .macOS) == .detail)
    }

    @Test("iOS keeps Get Mail and New Message above the message list")
    func iOSKeepsMailboxActionsInTheListSection() {
        #expect(MailRootMailboxActionToolbarPolicy.section(platform: .iOS) == .messageList)
    }

    @Test("a section renders the mailbox actions only when it owns them")
    func sectionRendersMailboxActionsOnlyWhenItOwnsThem() {
        for platform in [MailRootToolbarPlatform.macOS, .iOS] {
            let owner = MailRootMailboxActionToolbarPolicy.section(platform: platform)

            for section in MailRootMailboxActionToolbarSection.allCases {
                #expect(
                    MailRootMailboxActionToolbarPolicy.showsMailboxActions(
                        on: section,
                        platform: platform
                    ) == (section == owner)
                )
            }
        }
    }
}
