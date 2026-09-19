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
