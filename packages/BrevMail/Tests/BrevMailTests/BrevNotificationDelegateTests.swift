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

@Suite("BrevNotificationDelegate")
struct BrevNotificationDelegateTests {
    @Test("cold-launch inline reply waits for handler installation")
    func coldLaunchReplyWaitsForHandlerInstallation() async {
        let delegate = BrevNotificationDelegate()
        let recorder = NotificationReplyRecorder()
        let route = NotificationMailRoute(
            accountID: "acct-1",
            folderID: "inbox",
            messageID: "msg-1"
        )

        #expect(await recorder.replies.isEmpty)
        await withCheckedContinuation { completion in
            delegate.handleReply(
                route: route,
                userText: "  Thanks!  ",
                completionHandler: { completion.resume() }
            )

            #expect(delegate.pendingReplyCount == 1)

            delegate.onReply = { route, text in
                await recorder.record(route: route, text: text)
            }
        }

        #expect(delegate.pendingReplyCount == 0)
        #expect(await recorder.replies == [NotificationReplyRecord(route: route, text: "Thanks!")])
    }
}

private struct NotificationReplyRecord: Equatable, Sendable {
    let route: NotificationMailRoute
    let text: String
}

private actor NotificationReplyRecorder {
    private(set) var replies: [NotificationReplyRecord] = []

    func record(route: NotificationMailRoute, text: String) {
        replies.append(NotificationReplyRecord(route: route, text: text))
    }
}
