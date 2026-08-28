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

@testable import BrevDesign
import Testing

@Suite("Mailbox list density")
struct MailboxListDensityTests {
    @Test("density controls shared workspace chrome without changing its three-mode contract")
    func densityControlsSharedWorkspaceChrome() {
        #expect(MailboxListDensity.allCases == [.compact, .comfortable, .spacious])

        #expect(MailboxListDensity.compact.sidebarRowVerticalPadding == 2)
        #expect(MailboxListDensity.comfortable.sidebarRowVerticalPadding == 5)
        #expect(MailboxListDensity.spacious.sidebarRowVerticalPadding == 8)

        #expect(MailboxListDensity.compact.chromeVerticalPadding == 3)
        #expect(MailboxListDensity.comfortable.chromeVerticalPadding == 6)
        #expect(MailboxListDensity.spacious.chromeVerticalPadding == 8)

        #expect(MailboxListDensity.compact.metadataSpacing == 3)
        #expect(MailboxListDensity.comfortable.metadataSpacing == 8)
        #expect(MailboxListDensity.spacious.metadataSpacing == 12)
    }
}
