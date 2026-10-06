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
@testable import BrevSettings
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@Suite("Compact settings rows", .serialized)
@MainActor
struct CompactSettingsRowSnapshotTests {
    @Test("appearance controls stack at accessibility text sizes", arguments: [false, true])
    func accessibleAppearance(dark: Bool) throws {
        let suite = "AccessibleAppearance-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = AppearanceThemeSettings.defaults
        settings.mode = dark ? .alwaysDark : .alwaysLight
        settings.accentSource = .custom
        settings.accentHex = dark ? "#000000" : "#FFFFFF"
        settings.save(to: defaults)
        let theme = settings.resolvedTheme(prefersDark: dark)
        let view = AppearanceSection(
            activeTheme: .constant(theme),
            activeAppIcon: .constant(.defaultVariant),
            settingsStore: SettingsPersistenceStore(defaults: defaults)
        )
        .brevTheme(theme)
        .tint(theme.accent.color)
        .environment(\.colorScheme, dark ? .dark : .light)
        .environment(\.dynamicTypeSize, .accessibility3)
        .background(theme.bgPrimary.color)
        let host = UIHostingController(rootView: view)
        assertSnapshot(of: host, as: .image(size: CGSize(width: 375, height: 1800),
                                            traits: .init(displayScale: 2)),
                       named: dark ? "appearance-accessible-dark" : "appearance-accessible-light",
                       record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil)
    }

    @Test("signature name and controls fit a narrow phone", arguments: [320.0, 375.0])
    func compactSignature(width: Double) throws {
        let defaults = try #require(UserDefaults(suiteName: "CompactSignatures-" + UUID().uuidString))
        let store = SettingsPersistenceStore(defaults: defaults)
        var settings = SignatureSettings.defaults
        _ = settings.addSignature(name: "Work signature", body: "Best regards", isEnabled: true)
        store.save(settings)
        let host = UIHostingController(rootView: SignatureSection(settingsStore: store)
            .brevTheme(.brevMonoLight).environment(\.colorScheme, .light))
        assertSnapshot(of: host, as: .image(size: CGSize(width: width, height: 900),
                                            traits: .init(displayScale: 2)), named: "signature-\(Int(width))")
    }

    @Test("template and local-rule actions fit narrow settings content", arguments: [216.0, 271.0])
    func compactRows(width: Double) {
        let view = VStack(spacing: 20) {
            TemplateRow(
                template: MessageTemplate(name: "Delivery follow-up", body: "Thanks for the update. Please confirm delivery."),
                scopeTitle: "All accounts",
                onPin: {},
                onMoveUp: {},
                onMoveDown: {},
                canMoveUp: true,
                canMoveDown: true,
                onEdit: {},
                onDelete: {}
            )
            LocalRuleRow(rule: ServerRule(id: "rule", name: "Invoices from suppliers", isEnabled: true,
                                          conditions: [.subjectContains("Invoice")], actions: [.flag]),
                         isFirst: false, isLast: false, onToggle: { _ in }, onEdit: {},
                         onMoveUp: {}, onMoveDown: {}, onDelete: {})
            Spacer()
        }
        .brevTheme(.brevMonoLight)
        .environment(\.colorScheme, .light)
        let host = UIHostingController(rootView: view)
        assertSnapshot(of: host, as: .image(size: CGSize(width: width, height: 420),
                                            traits: .init(displayScale: 2)), named: "compact-\(Int(width))")
    }
}
#endif
