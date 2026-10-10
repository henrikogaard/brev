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

/// The phone list title is the navigation title; the unread count moves to its subtitle
/// (audit L5).
@Suite("Message list subtitle")
struct MailRootMessageListSubtitleTests {
    @Test("the subtitle is the unread count")
    func subtitleIsUnreadCount() {
        // Catalogs are not compiled under `swift test`, so the English key is what resolves.
        #expect(MailRootMessageListTitlePolicy.subtitle(unreadCount: 5) == "5 unread")
    }

    @Test("the subtitle is absent without unread mail")
    func subtitleAbsentWithoutUnread() {
        #expect(MailRootMessageListTitlePolicy.subtitle(unreadCount: nil) == nil)
        #expect(MailRootMessageListTitlePolicy.subtitle(unreadCount: 0) == nil)
    }
}
