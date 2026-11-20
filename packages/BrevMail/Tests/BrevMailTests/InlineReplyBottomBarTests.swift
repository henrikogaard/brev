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

/// The docked reply's bottom bar (#302 slice 3).
@Suite("Inline reply bottom bar")
struct InlineReplyBottomBarTests {
    @Test("Send, Later, Write, then attach and format")
    func fullBar() {
        #expect(InlineReplyBottomBar.items(canScheduleSend: true, offersAIWriter: true)
            == [.send, .later, .write, .attach, .format])
    }

    @Test("Later is left out when the account cannot schedule sends")
    func noSchedule() {
        #expect(InlineReplyBottomBar.items(canScheduleSend: false, offersAIWriter: true)
            == [.send, .write, .attach, .format])
    }

    @Test("Write is left out when the account has no AI Writer")
    func noAIWriter() {
        #expect(InlineReplyBottomBar.items(canScheduleSend: true, offersAIWriter: false)
            == [.send, .later, .attach, .format])
    }
}
