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
import BrevAI
import BrevBackend
import BrevDesign
@testable import BrevSettings
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

@Suite("BrevSettings snapshots")
struct BrevSettingsSnapshotTests {
    @Test("AppearanceSection renders in every built-in theme", arguments: BrevTheme.brevBuiltIns)
    @MainActor
    func appearanceSectionRendersInTheme(_ theme: BrevTheme) throws {
        let view = AppearanceSectionContainer()
            .frame(width: 380, height: 900)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)

        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear

        assertSnapshot(
            of: host,
            as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
            named: theme.id
        )
    }

    @Test("MailboxViewSection renders in every built-in theme", arguments: BrevTheme.brevBuiltIns)
    @MainActor
    func mailboxViewSectionRendersInTheme(_ theme: BrevTheme) throws {
        let view = MailboxViewSectionContainer()
            .frame(width: 380, height: 900)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)

        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear

        assertSnapshot(
            of: host,
            as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
            named: theme.id
        )
    }

    @Test("PrivacySection renders in every built-in theme", arguments: BrevTheme.brevBuiltIns)
    @MainActor
    func privacySectionRendersInTheme(_ theme: BrevTheme) throws {
        let view = PrivacySectionContainer()
            .frame(width: 380, height: 1020)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)

        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear

        assertSnapshot(
            of: host,
            as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
            named: theme.id
        )
    }

    @Test("SignatureSection renders in default theme")
    @MainActor
    func signatureSectionRendersInTheme() throws {
        let defaults = try Self.makeDefaults(named: "signature")
        var settings = SignatureSettings.defaults
        let work = settings.addSignature(name: "Work", body: "Henrik\nBrev", isEnabled: true)
        _ = settings.addSignature(name: "Personal", body: "Henrik", isEnabled: true)
        settings.setDefaultSignature(signatureID: work.id, forAccountID: "acct-1")
        settings.save(to: defaults)

        let view = SignatureSectionContainer(
            settingsStore: SettingsPersistenceStore(defaults: defaults),
            accounts: [
                BrevAccount(id: "acct-1", displayName: "Work", emailAddress: "work@example.org"),
                BrevAccount(id: "acct-2", displayName: "Personal", emailAddress: "personal@example.org")
            ]
        )
        .frame(width: 540, height: 980)
        .background(BrevTheme.brevPaper.bgPrimary.color)
        .brevTheme(.brevPaper)

        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear

        assertSnapshot(
            of: host,
            as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
            named: "default"
        )
    }

    @Test("AIWriterSection renders default and enabled states", arguments: AIWriterSectionSnapshotState.allCases)
    @MainActor
    func aiWriterSectionRendersStates(_ state: AIWriterSectionSnapshotState) throws {
        let defaults = try Self.makeDefaults(named: state.rawValue)
        state.settings.save(to: defaults)
        let view = AIWriterSectionContainer(settingsStore: SettingsPersistenceStore(defaults: defaults))
            .frame(width: 380, height: 520)
            .background(BrevTheme.brevPaper.bgPrimary.color)
            .brevTheme(.brevPaper)

        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear

        assertSnapshot(
            of: host,
            as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
            named: state.rawValue
        )
    }

    private static func makeDefaults(named name: String) throws -> UserDefaults {
        let suiteName = "BrevSettingsSnapshotTests-\(name)-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private struct AppearanceSectionContainer: View {
    @State private var activeTheme: BrevTheme = .brevPaper
    @State private var activeAppIcon = AppIconVariant.defaultVariant

    var body: some View {
        AppearanceSection(
            activeTheme: $activeTheme,
            activeAppIcon: $activeAppIcon
        )
    }
}

private struct MailboxViewSectionContainer: View {
    var body: some View {
        MailboxViewSection()
    }
}

private enum AIWriterSectionSnapshotState: String, CaseIterable {
    case disabled
    case enabled

    var settings: AIWriterSettings {
        switch self {
        case .disabled:
            return .defaults
        case .enabled:
            return AIWriterSettings(isEnabled: true, consentGiven: true)
        }
    }
}

private struct AIWriterSectionContainer: View {
    let settingsStore: SettingsPersistenceStore

    var body: some View {
        AIWriterSection(settingsStore: settingsStore)
    }
}

private struct ComposeSectionContainer: View {
    var body: some View {
        ComposeSection()
    }
}

private struct SignatureSectionContainer: View {
    let settingsStore: SettingsPersistenceStore
    let accounts: [BrevAccount]

    var body: some View {
        SignatureSection(settingsStore: settingsStore, accounts: accounts)
    }
}

private struct PrivacySectionContainer: View {
    var body: some View {
        PrivacySection()
    }
}

private struct NotificationSectionContainer: View {
    var body: some View {
        NotificationSection()
    }
}

private struct AccountsSectionContainer: View {
    let accounts: [BrevAccount]

    var body: some View {
        AccountsSection(
            accounts: accounts,
            currentAccountID: accounts.first?.id,
            onAddAccount: {},
            onSetDefault: { _ in },
            onSignOut: { _ in },
            onRemoveAccount: { _ in }
        )
    }
}
#endif

#if os(macOS)
import AppKit
import BrevAI
import BrevBackend
import BrevDesign
@testable import BrevSettings
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

@Suite("AI Writer macOS snapshots")
@MainActor
struct AIWriterSectionMacSnapshotTests {
    @Test("Settings navigation presents searchable task groups")
    func settingsNavigationPresentsSearchableTaskGroups() {
        let theme = BrevTheme.brevPaper
        let view = SettingsViewSnapshotContainer()
            .frame(width: 900, height: 650)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)
        let host = NSHostingController(rootView: view)

        assertSnapshot(
            of: Self.retinaImage(of: host, size: CGSize(width: 900, height: 650)),
            as: .image,
            named: "settings-navigation",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES"
        )
    }

    @Test("AI Writer presents a guided provider setup when none is saved")
    func providerSetupRenders() throws {
        // SwiftUI's form, material, and control rendering differs across major
        // macOS releases. This baseline was recorded for the macOS 26+ design;
        // older CI hosts still compile the view and run the structural smoke
        // suite without comparing pixels from a different renderer.
        guard #available(macOS 26.0, *) else { return }

        let suiteName = "AIWriterSectionMacSnapshotTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let theme = BrevTheme.brevPaper
        let view = AIWriterSection(settingsStore: SettingsPersistenceStore(defaults: defaults))
            .frame(width: 680, height: 460)
            .background(theme.bgPrimary.color)
            .brevTheme(theme)
        let host = NSHostingController(rootView: view)

        assertSnapshot(
            of: Self.retinaImage(of: host, size: CGSize(width: 680, height: 460)),
            as: .image,
            named: "provider-setup",
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    private static func retinaImage<Content: View>(
        of host: NSHostingController<Content>,
        size: CGSize
    ) -> NSImage {
        let view = host.view
        let originalSize = view.frame.size
        view.frame.size = size
        view.layoutSubtreeIfNeeded()
        defer { view.frame.size = originalSize }

        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2),
            pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: .alphaFirst,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        bitmap.size = size
        view.cacheDisplay(in: view.bounds, to: bitmap)

        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        return image
    }
}

private struct SettingsViewSnapshotContainer: View {
    @State private var theme = BrevTheme.brevPaper

    var body: some View {
        SettingsView(
            accountStore: InMemoryAccountStore(),
            activeTheme: $theme
        )
    }
}
#endif
