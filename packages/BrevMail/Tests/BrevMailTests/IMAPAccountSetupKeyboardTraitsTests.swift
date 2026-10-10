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

#if canImport(UIKit)
import BrevBackend
@testable import BrevMail
import BrevThemes
import SwiftUI
import Testing
import UIKit

/// Reads the UIKit traits SwiftUI applies to the add-account fields, so the
/// Keychain autofill hints and Return key stay pinned (iOS UX audit O1).
@Suite("Add-account keyboard traits")
@MainActor
struct IMAPAccountSetupKeyboardTraitsTests {
    @Test("the email field offers Keychain credentials and a Go key that runs Find settings")
    func emailFieldTraits() async throws {
        let session = AppSession(
            accountStore: InMemoryAccountStore(),
            tokenStore: TraitsTokenStore(),
            imapAccountSetupCoordinator: { _ in fatalError("not called") },
            imapAccountDiscoveryCoordinator: { _ in fatalError("not called") }
        )
        let host = UIHostingController(
            rootView: IMAPAccountSetupSheet(session: session, onClose: {})
                .brevTheme(BrevTheme.brevMonoLight)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(600))
        host.view.layoutIfNeeded()

        let fields = textFields(in: host.view)
        let email = try #require(fields.first { $0.keyboardType == .emailAddress })
        #expect(email.textContentType == .username)
        #expect(email.returnKeyType == .go)
        #expect(email.autocapitalizationType == .none)
        #expect(email.autocorrectionType == .no)
    }

    private func textFields(in view: UIView) -> [UITextField] {
        var result: [UITextField] = []
        if let field = view as? UITextField { result.append(field) }
        for subview in view.subviews {
            result += textFields(in: subview)
        }
        return result
    }
}

private actor TraitsTokenStore: TokenStore {
    func token(for accountID: String) async -> Token? { nil }
    func setToken(_ token: Token, for accountID: String) async throws {}
    func clearToken(for accountID: String) async {}
}
#endif
