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
import UIKit

@Suite("iPhone mailbox layout")
@MainActor
struct MailboxLayoutTests {
    @Test("search remains a single row when its parent offers the whole screen")
    func searchDoesNotConsumeMailboxHeight() async throws {
        let host = UIHostingController(rootView:
            VStack(spacing: 0) {
                MessageListSearchField(text: .constant(""), prompt: "Search messages")
                Color.clear.frame(maxHeight: .infinity)
            })
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(100))
        host.view.layoutIfNeeded()
        let field = try #require(findTextField(in: host.view))
        #expect(field.bounds.height >= 44)
        #expect(field.bounds.height <= 52)
    }

    private func findTextField(in view: UIView) -> UITextField? {
        if let field = view as? UITextField { return field }
        return view.subviews.lazy.compactMap { findTextField(in: $0) }.first
    }
}
