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
    private var reviewFixture: SettingsReviewFixture?

    func scene(_ scene: UIScene, willConnectTo _: UISceneSession, options _: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        do {
            if let selection = try SettingsReviewSelection.parse(ProcessInfo.processInfo.environment) {
                let fixture = try SettingsReviewFixture(
                    variant: selection.variant, suite: "SettingsNativeReview",
                    quietHoursEnabled: selection.pane == .notificationsQuietHours
                )
                reviewFixture = fixture
                let controller = UIHostingController(rootView: SeededSettingsReview(fixture: fixture, selection: selection))
                controller.traitOverrides.preferredContentSizeCategory = selection.variant == .ax3
                    ? .accessibilityExtraLarge : .large
                window.overrideUserInterfaceStyle = selection.variant.isDark ? .dark : .light
                window.rootViewController = controller
            } else {
                window.rootViewController = UIHostingController(rootView: SyntheticSettings())
            }
        } catch {
            preconditionFailure("Invalid synthetic Settings review configuration: \(error)")
        }
        self.window = window
        window.makeKeyAndVisible()
    }

    func sceneDidDisconnect(_: UIScene) {
        reviewFixture?.cleanUp()
        reviewFixture = nil
    }
}

private struct SeededSettingsReview: View {
    let fixture: SettingsReviewFixture
    let selection: SettingsReviewSelection
    @State private var pimModel: PIMSourceSettingsModel?

    var body: some View {
        fixture.styled(pane, variant: selection.variant)
            .task {
                guard selection.pane == .pimSources else { return }
                do { pimModel = try await PIMSourcesFixture.model() }
                catch { preconditionFailure("Unable to load synthetic PIM fixtures: \(error)") }
            }
    }

    @ViewBuilder private var pane: some View {
        switch selection.pane {
        case .appearance: fixture.appearance
        case .notifications, .notificationsQuietHours: fixture.notifications
        case .signInCodes: fixture.signInCodes
        case .pimSources:
            if let pimModel { fixture.pimSources(pimModel) }
            else { ProgressView() }
        }
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
