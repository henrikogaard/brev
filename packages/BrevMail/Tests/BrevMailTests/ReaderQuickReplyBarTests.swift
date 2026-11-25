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
import BrevThemes
import SwiftUI
import Testing
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@Suite("ReaderQuickReplyBar")
struct ReaderQuickReplyBarTests {
    @Test("send and auxiliary button targets match platform HIG sizes")
    func buttonTargetSizes() {
        #expect(ReaderQuickReplyLayoutPolicy.sendButtonSize(isTouchPlatform: false) == 34)
        #expect(ReaderQuickReplyLayoutPolicy.sendButtonSize(isTouchPlatform: true) == 44)
        #expect(ReaderQuickReplyLayoutPolicy.auxiliaryButtonSize(isTouchPlatform: false) == 28)
        #expect(ReaderQuickReplyLayoutPolicy.auxiliaryButtonSize(isTouchPlatform: true) == 44)
        #expect(ReaderQuickReplyLayoutPolicy.inputCornerRadius == 20)
    }

    @Test("canSend requires non-whitespace draft text and an enabled idle bar")
    func canSendPolicy() {
        #expect(!ReaderQuickReplyLayoutPolicy.canSend(draftText: "", isDisabled: false, isSending: false))
        #expect(!ReaderQuickReplyLayoutPolicy.canSend(draftText: "   \n\t ", isDisabled: false, isSending: false))
        #expect(!ReaderQuickReplyLayoutPolicy.canSend(draftText: "Sounds good", isDisabled: true, isSending: false))
        #expect(!ReaderQuickReplyLayoutPolicy.canSend(draftText: "Sounds good", isDisabled: false, isSending: true))
        #expect(ReaderQuickReplyLayoutPolicy.canSend(draftText: "Sounds good", isDisabled: false, isSending: false))
    }

    @Test("quick reply bar and bottom fade lay out cleanly in light and dark themes", arguments: [false, true])
    @MainActor
    func barAndBottomFadeLayout(dark: Bool) {
        let theme = dark ? BrevTheme.brevMonoDark : .brevMonoLight
        let view = ReaderQuickReplyBar(
            recipientName: "Ada Nyström",
            onSend: { _ in true },
            onExpand: { _ in },
            isDisabled: false
        )
        .background {
            ReaderQuickReplyBottomFade()
        }
        .brevTheme(theme)
        .environment(\.colorScheme, dark ? .dark : .light)

        #if os(macOS)
        let host = NSHostingController(rootView: view)
        host.view.frame = NSRect(x: 0, y: 0, width: 480, height: 80)
        host.view.layoutSubtreeIfNeeded()
        #expect(host.view.fittingSize.height >= 48)
        #elseif canImport(UIKit)
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 80)
        host.view.layoutIfNeeded()
        #expect(host.sizeThatFits(in: CGSize(width: 390, height: 80)).height >= 56)
        #endif
    }
}
