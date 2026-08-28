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
import SwiftUI
import Testing

@Suite("Message list sender presentation")
struct MessageListSenderPresentationTests {
    @Test("sender identity stays bold for read and unread rows")
    func senderIdentityStaysBold() {
        #expect(MessageListSenderPresentation.fontWeight == .bold)
    }

    @Test("compact rows keep the sender and subject while removing secondary metadata")
    func compactRowsKeepPrimaryMailIdentity() {
        let compact = MessageListRowContentPolicy.presentation(
            isCompactWidth: true,
            requestedPreviewLineCount: 2
        )

        #expect(!compact.showsSourceContext)
        #expect(!compact.showsLabelChips)
        #expect(compact.previewLineCount == 0)
        #expect(!compact.showsStatusIcons)
    }

    @Test("regular rows preserve configured metadata and preview")
    func regularRowsPreserveConfiguredMetadata() {
        let regular = MessageListRowContentPolicy.presentation(
            isCompactWidth: false,
            requestedPreviewLineCount: 2
        )

        #expect(regular.showsSourceContext)
        #expect(regular.showsLabelChips)
        #expect(regular.previewLineCount == 2)
        #expect(regular.showsStatusIcons)
    }
}
