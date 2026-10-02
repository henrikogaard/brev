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
#if os(macOS)
import AppKit
import SwiftUI
#endif

@Suite("Mailbox list density")
struct MailboxListDensityTests {
    @Test("platform default density follows the platform")
    func platformDefaultMatchesPlatform() {
        #if os(macOS)
        #expect(MailboxListDensity.platformDefault == .compact)
        #else
        #expect(MailboxListDensity.platformDefault == .comfortable)
        #endif
    }

    #if os(macOS)
    @Test("desktop text size updates an already mounted interface label")
    @MainActor
    func desktopTextSizeUpdatesMountedLabel() throws {
        let suite = "BrevDesktopSizingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(MailboxTextSize.small.rawValue, forKey: MailboxViewPreferenceKey.textSize)
        let host = NSHostingView(rootView: Text("Mailbox settings")
            .brevFont(.body)
            .fixedSize()
            .defaultAppStorage(defaults))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let small = host.fittingSize
        defaults.set(MailboxTextSize.large.rawValue, forKey: MailboxViewPreferenceKey.textSize)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()
        let large = host.fittingSize
        #expect(large.width > small.width)
        #expect(large.height > small.height)
        window.contentView = nil
    }
    #endif

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
