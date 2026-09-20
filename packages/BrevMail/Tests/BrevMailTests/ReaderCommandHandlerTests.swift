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

#if os(iOS)
import BrevBackend
@testable import BrevMail
import SwiftUI
import Testing
import UIKit

@Suite("Reader command owner", .serialized)
@MainActor
struct ReaderCommandHandlerTests {
    @Test("reader keeps one action identity while dispatching to the latest owner")
    func latestOwnerWithoutEnvironmentChurn() async throws {
        let capture = ActionCapture()
        var calledOwner = 0
        let host = UIHostingController(rootView: ActionProbe(capture: capture)
            .readerCommandHandler { _ in calledOwner = 1 })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        await Task.yield()
        let first = try #require(capture.action)
        let header = MessageHeader(id: "message", threadID: "thread", folderID: "inbox",
                                   from: Correspondent(email: "sender@example.org"),
                                   subject: "Subject", snippet: "", date: .distantPast)
        let request = DetachedMessageCommandRequest(command: .reply, header: header, sourceID: nil)
        first(request)
        #expect(calledOwner == 1)

        host.rootView = ActionProbe(capture: capture).readerCommandHandler { _ in calledOwner = 2 }
        host.view.layoutIfNeeded()
        await Task.yield()
        #expect(capture.action === first)
        first(request)
        #expect(calledOwner == 2)
    }
}

@MainActor
private final class ActionCapture {
    var action: ReaderCommandAction?
}

private struct ActionProbe: View {
    @Environment(\.readerCommandAction) private var action
    let capture: ActionCapture

    var body: some View {
        let _ = capture.action = action
        Color.clear
    }
}
#endif
