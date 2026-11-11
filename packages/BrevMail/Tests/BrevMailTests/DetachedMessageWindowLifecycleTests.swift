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

#if os(macOS)
import AppKit
import BrevBackend
import BrevDesign
@testable import BrevMail
import BrevThemes
import Testing

/// A detached reader must close cleanly and be freed exactly once (#286).
@Suite("Detached reader lifecycle", .serialized)
@MainActor
struct DetachedMessageWindowLifecycleTests {
    @Test("closing a detached reader frees it without an over-release")
    func closeFreesWindowOnce() async throws {
        _ = NSApplication.shared
        weak var closed: NSWindow?
        for index in 0 ..< 3 {
            let before = Set(NSApp.windows.map(ObjectIdentifier.init))
            DetachedMessageWindow.open(
                header: Self.header(index),
                backend: MockBackend(),
                sourceID: nil,
                allFolders: [],
                canFileLocally: false,
                theme: .brevPaper,
                onCommand: { _ in true }
            )
            let window = try #require(NSApp.windows.first { !before.contains(ObjectIdentifier($0)) })
            #expect(window.isReleasedWhenClosed == false)
            closed = window
            window.performClose(nil)
            // Drain the run loop and autorelease pools so a double release
            // would crash here rather than later.
            for _ in 0 ..< 20 {
                autoreleasepool {
                    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
                }
                await Task.yield()
            }
        }
        #expect(closed == nil)
    }

    private static func header(_ index: Int) -> MessageHeader {
        MessageHeader(
            id: "inbox:detached-\(index)",
            threadID: "thread-detached-\(index)",
            folderID: "inbox",
            from: Correspondent(name: "Avery Kim", email: "avery@example.org"),
            subject: "Lifecycle \(index)",
            snippet: "Closing a reader keeps the app running.",
            date: Date(timeIntervalSince1970: 1_779_960_600)
        )
    }
}
#endif
