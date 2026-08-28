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
import BrevDesign
@testable import BrevSettings
import BrevThemes
import Foundation
import SwiftUI
import Testing
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@Suite("Compact settings view smoke")
struct CompactSettingsViewSmokeTests {
    @Test("settings entry point renders at compact desktop size")
    @MainActor
    func settingsEntryPointRendersAtCompactDesktopSize() async throws {
        let account = BrevAccount(
            id: "compact-settings-account",
            displayName: "Brev Test",
            emailAddress: "test@example.org"
        )
        let view = CompactSettingsViewContainer(
            accountStore: InMemoryAccountStore(accounts: [account], current: account)
        )

        #if os(macOS)
        let image = try await renderMacImage(
            view
                .frame(width: 860, height: 600)
                .background(BrevTheme.brevPaper.bgPrimary.color)
                .brevTheme(.brevPaper),
            width: 860,
            height: 600
        )
        try recordArtifactIfRequested(image, name: "settings-860x600")
        #elseif canImport(UIKit)
        let image = ImageRenderer(
            content: view
                .frame(width: 860, height: 600)
                .background(BrevTheme.brevPaper.bgPrimary.color)
                .brevTheme(.brevPaper)
        )
        image.scale = 2
        try recordArtifactIfRequested(#require(image.uiImage), name: "settings-860x600")
        #else
        Issue.record("No supported image renderer is available on this platform.")
        #endif
    }

    @Test("settings entry point renders at normal desktop size")
    @MainActor
    func settingsEntryPointRendersAtNormalDesktopSize() async throws {
        let account = BrevAccount(
            id: "normal-settings-account",
            displayName: "Brev Test",
            emailAddress: "test@example.org"
        )
        let view = CompactSettingsViewContainer(
            accountStore: InMemoryAccountStore(accounts: [account], current: account)
        )

        #if os(macOS)
        let image = try await renderMacImage(
            view
                .frame(width: 1100, height: 760)
                .background(BrevTheme.brevPaper.bgPrimary.color)
                .brevTheme(.brevPaper),
            width: 1100,
            height: 760
        )
        try recordArtifactIfRequested(image, name: "settings-1100x760")
        #elseif canImport(UIKit)
        let image = ImageRenderer(
            content: view
                .frame(width: 1100, height: 760)
                .background(BrevTheme.brevPaper.bgPrimary.color)
                .brevTheme(.brevPaper)
        )
        image.scale = 2
        try recordArtifactIfRequested(#require(image.uiImage), name: "settings-1100x760")
        #else
        Issue.record("No supported image renderer is available on this platform.")
        #endif
    }

    @Test("security settings render the S/MIME-only baseline")
    @MainActor
    func securitySettingsRenderSMIMEOnly() async throws {
        let view = CompactSettingsViewContainer(
            accountStore: InMemoryAccountStore(),
            initialSection: .security
        )

        #if os(macOS)
        let image = try await renderMacImage(
            view
                .frame(width: 860, height: 760)
                .background(BrevTheme.brevPaper.bgPrimary.color)
                .brevTheme(.brevPaper),
            width: 860,
            height: 760
        )
        try recordArtifactIfRequested(image, name: "security-smime-only-860x760")
        #elseif canImport(UIKit)
        let image = ImageRenderer(
            content: view
                .frame(width: 860, height: 760)
                .background(BrevTheme.brevPaper.bgPrimary.color)
                .brevTheme(.brevPaper)
        )
        image.scale = 2
        try recordArtifactIfRequested(#require(image.uiImage), name: "security-smime-only-860x760")
        #else
        Issue.record("No supported image renderer is available on this platform.")
        #endif
    }

    @Test("compose settings render recipient suggestions and local recipient controls")
    @MainActor
    func composeSettingsRenderRecipientSuggestions() async throws {
        let defaults = try Self.makeDefaults(named: "recipient-suggestions")
        RecentRecipientStore(defaults: defaults).record([
            RecentRecipientObservation(
                accountID: "compose-settings-account",
                displayName: "Ada Lovelace",
                email: "ada@example.org",
                date: Date(timeIntervalSince1970: 1_700_000_000)
            )
        ])
        let view = CompactSettingsViewContainer(
            accountStore: InMemoryAccountStore(),
            initialSection: .compose,
            settingsStore: SettingsPersistenceStore(defaults: defaults)
        )

        #if os(macOS)
        let image = try await renderMacImage(
            view
                .frame(width: 1100, height: 980)
                .background(BrevTheme.brevPaper.bgPrimary.color)
                .brevTheme(.brevPaper),
            width: 1100,
            height: 980
        )
        try recordArtifactIfRequested(image, name: "compose-recipient-suggestions-1100x980")
        #elseif canImport(UIKit)
        let image = ImageRenderer(
            content: view
                .frame(width: 1100, height: 980)
                .background(BrevTheme.brevPaper.bgPrimary.color)
                .brevTheme(.brevPaper)
        )
        image.scale = 2
        try recordArtifactIfRequested(#require(image.uiImage), name: "compose-recipient-suggestions-1100x980")
        #else
        Issue.record("No supported image renderer is available on this platform.")
        #endif
    }

    @Test("appearance section renders message-content opacity controls")
    @MainActor
    func appearanceSectionRendersMessageContentOpacityControls() async throws {
        let defaults = try Self.makeDefaults(named: "appearance-message-content-opacity")
        WindowAppearancePreferences(
            mode: .frosted,
            scope: .mainWindow,
            surfaceOpacity: 0.72,
            sidebarOpacity: 0.48,
            messageContentOpacityMode: .custom,
            messageContentOpacity: 1
        ).save(to: defaults)
        let view = CompactSettingsViewContainer(
            accountStore: InMemoryAccountStore(),
            initialSection: .appearance,
            settingsStore: SettingsPersistenceStore(defaults: defaults)
        )

        #if os(macOS)
        let image = try await renderMacImage(
            view
                .frame(width: 1100, height: 1900)
                .background(BrevTheme.brevPaper.bgPrimary.color)
                .brevTheme(.brevPaper),
            width: 1100,
            height: 1900
        )
        try recordArtifactIfRequested(image, name: "appearance-message-opacity-1100x1900")
        #elseif canImport(UIKit)
        let image = ImageRenderer(
            content: view
                .frame(width: 1100, height: 1900)
                .background(BrevTheme.brevPaper.bgPrimary.color)
                .brevTheme(.brevPaper)
        )
        image.scale = 2
        try recordArtifactIfRequested(#require(image.uiImage), name: "appearance-message-opacity-1100x1900")
        #else
        Issue.record("No supported image renderer is available on this platform.")
        #endif
    }

    @Test("settings entry point can open Mail Storage at desktop size")
    @MainActor
    func settingsEntryPointCanOpenMailStorageAtDesktopSize() async throws {
        let account = BrevAccount(
            id: "settings-mail-storage-account",
            displayName: "Storage Test",
            emailAddress: "storage@example.org"
        )
        let view = try CompactSettingsViewContainer(
            accountStore: InMemoryAccountStore(accounts: [account], current: account),
            initialSection: .mailStorage,
            initialAccounts: [account],
            initialCurrentAccountID: account.id,
            settingsStore: SettingsPersistenceStore(defaults: Self.makeDefaults(named: "settings-mail-storage")),
            backend: MockBackend(account: account)
        )

        #if os(macOS)
        let image = try await renderMacImage(
            view
                .frame(width: 1100, height: 760)
                .background(BrevTheme.brevPaper.bgPrimary.color)
                .brevTheme(.brevPaper),
            width: 1100,
            height: 760
        )
        try recordArtifactIfRequested(image, name: "settings-mail-storage-1100x760")
        #elseif canImport(UIKit)
        let image = ImageRenderer(
            content: view
                .frame(width: 1100, height: 760)
                .background(BrevTheme.brevPaper.bgPrimary.color)
                .brevTheme(.brevPaper)
        )
        image.scale = 2
        try recordArtifactIfRequested(#require(image.uiImage), name: "settings-mail-storage-1100x760")
        #else
        Issue.record("No supported image renderer is available on this platform.")
        #endif
    }

    @Test("mail storage section renders at desktop size")
    @MainActor
    func mailStorageSectionRendersAtDesktopSize() async throws {
        let account = BrevAccount(
            id: "mail-storage-settings-account",
            displayName: "Storage Test",
            emailAddress: "storage@example.org"
        )
        let defaults = try Self.makeDefaults(named: "mail-storage")
        let view = MailStorageSectionContainer(
            account: account,
            backend: MockBackend(account: account),
            settingsStore: SettingsPersistenceStore(defaults: defaults)
        )

        #if os(macOS)
        let image = try await renderMacImage(
            view
                .frame(width: 860, height: 760)
                .background(BrevTheme.brevPaper.bgPrimary.color)
                .brevTheme(.brevPaper),
            width: 860,
            height: 760
        )
        try recordArtifactIfRequested(image, name: "mail-storage-section-860x760")
        #elseif canImport(UIKit)
        let image = ImageRenderer(
            content: view
                .frame(width: 860, height: 760)
                .background(BrevTheme.brevPaper.bgPrimary.color)
                .brevTheme(.brevPaper)
        )
        image.scale = 2
        try recordArtifactIfRequested(#require(image.uiImage), name: "mail-storage-section-860x760")
        #else
        Issue.record("No supported image renderer is available on this platform.")
        #endif
    }

    @Test("mail storage cache lookback selection stays readable in a light theme")
    @MainActor
    func mailStorageCacheLookbackSelectionStaysReadableInLightTheme() async throws {
        #if os(macOS)
        let account = BrevAccount(
            id: "mail-storage-picker-contrast-account",
            displayName: "Storage Test",
            emailAddress: "storage@example.org"
        )
        let defaults = try Self.makeDefaults(named: "mail-storage-picker-contrast")
        let view = MailStorageSectionContainer(
            account: account,
            backend: MockBackend(account: account),
            settingsStore: SettingsPersistenceStore(defaults: defaults),
            initiallyAdvancedExpanded: true
        )
        let image = try await renderMacImage(
            view
                .frame(width: 860, height: 760)
                .background(BrevTheme.brevPaper.bgPrimary.color)
                .brevTheme(.brevPaper),
            width: 860,
            height: 760
        )
        try recordArtifactIfRequested(image, name: "mail-storage-expanded-cache-lookback-860x760")

        let darkPixels = try darkPixelCount(
            in: image,
            // Cover the retention picker after the cardless Settings rhythm
            // moved the control lower in the rendered pane.
            logicalRect: NSRect(x: 650, y: 480, width: 110, height: 90),
            logicalSize: NSSize(width: 860, height: 760)
        )
        #expect(darkPixels > 100)
        #else
        Issue.record("The light-theme contrast assertion uses AppKit rendering.")
        #endif
    }

    private static func makeDefaults(named name: String) throws -> UserDefaults {
        let suiteName = "CompactSettingsViewSmokeTests-\(name)-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    #if os(macOS)
    @MainActor
    private func renderMacImage(_ view: some View, width: CGFloat, height: CGFloat) async throws -> NSImage {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hostingView.layoutSubtreeIfNeeded()
        await settleSwiftUITasks()
        hostingView.layoutSubtreeIfNeeded()

        let representation = try #require(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)

        let image = NSImage(size: hostingView.bounds.size)
        image.addRepresentation(representation)
        return image
    }

    @MainActor
    private func settleSwiftUITasks() async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 150_000_000)
        await Task.yield()
    }

    private func recordArtifactIfRequested(_ image: NSImage, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["BREV_COMPACT_LAYOUT_ARTIFACT_DIR"],
              !directory.isEmpty else {
            return
        }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
            .appendingPathComponent("\(name).png")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let representation = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init))
        let pngData = try #require(representation.representation(using: .png, properties: [:]))
        try pngData.write(to: url)
    }

    @MainActor
    private func darkPixelCount(
        in image: NSImage,
        logicalRect: NSRect,
        logicalSize: NSSize
    ) throws -> Int {
        let representation = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init))
        let horizontalScale = CGFloat(representation.pixelsWide) / logicalSize.width
        let verticalScale = CGFloat(representation.pixelsHigh) / logicalSize.height
        let pixelRect = NSRect(
            x: logicalRect.minX * horizontalScale,
            y: logicalRect.minY * verticalScale,
            width: logicalRect.width * horizontalScale,
            height: logicalRect.height * verticalScale
        ).integral.intersection(NSRect(
            x: 0,
            y: 0,
            width: representation.pixelsWide,
            height: representation.pixelsHigh
        ))
        var count = 0
        for x in Int(pixelRect.minX) ..< Int(pixelRect.maxX) {
            for y in Int(pixelRect.minY) ..< Int(pixelRect.maxY) {
                guard let color = representation.colorAt(x: x, y: y)?
                    .usingColorSpace(.deviceRGB)
                else { continue }
                if (color.redComponent + color.greenComponent + color.blueComponent) / 3 < 0.45 {
                    count += 1
                }
            }
        }
        return count
    }

    #elseif canImport(UIKit)
    private func recordArtifactIfRequested(_ image: UIImage, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["BREV_COMPACT_LAYOUT_ARTIFACT_DIR"],
              !directory.isEmpty else {
            return
        }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
            .appendingPathComponent("\(name).png")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let pngData = try #require(image.pngData())
        try pngData.write(to: url)
    }
    #endif
}

private struct CompactSettingsViewContainer: View {
    let accountStore: any AccountStore
    var initialSection: SettingsSection = .accounts
    var initialAccounts: [BrevAccount] = []
    var initialCurrentAccountID: BrevAccount.ID?
    var settingsStore: SettingsPersistenceStore = .standard
    var backend: MockBackend?
    @State private var activeTheme = BrevTheme.brevPaper

    var body: some View {
        SettingsView(
            accountStore: accountStore,
            activeTheme: $activeTheme,
            initialSection: initialSection,
            initialAccounts: initialAccounts,
            initialCurrentAccountID: initialCurrentAccountID,
            settingsStore: settingsStore,
            backendProvider: { accountID in
                guard let backend, backend.account.id == accountID else { return nil }
                return backend
            }
        )
    }
}

private struct MailStorageSectionContainer: View {
    let account: BrevAccount
    let backend: MockBackend
    let settingsStore: SettingsPersistenceStore
    var initiallyAdvancedExpanded = false

    var body: some View {
        MailStorageSection(
            account: account,
            backend: backend,
            settingsStore: settingsStore,
            initiallyAdvancedExpanded: initiallyAdvancedExpanded
        )
    }
}
