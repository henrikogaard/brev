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
import BrevSettings
import BrevThemes
import SwiftUI
import UIKit

@main
final class SnapshotHost: UIResponder, UIApplicationDelegate {
    func application(
        _: UIApplication,
        configurationForConnecting session: UISceneSession,
        options _: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Snapshots", sessionRole: session.role)
        configuration.delegateClass = SnapshotScene.self
        return configuration
    }
}

final class SnapshotScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo _: UISceneSession, options _: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: SyntheticSettings())
        self.window = window
        window.makeKeyAndVisible()
    }
}

private struct SyntheticSettings: View {
    @State private var theme = BrevTheme.brevPaper
    private let accountStore: InMemoryAccountStore

    init() {
        let account = BrevAccount(id: "demo", displayName: "Synthetic Account", emailAddress: "demo@brev.example")
        accountStore = InMemoryAccountStore(accounts: [account], current: account)
    }

    var body: some View {
        SettingsView(accountStore: accountStore, activeTheme: $theme)
            .brevTheme(theme)
    }
}
