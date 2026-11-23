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

#if os(macOS)
import AppKit
import BrevDesign
@testable import BrevMail
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

/// macOS snapshot coverage for Compose's "Later" action button beside Send in
/// enabled, scheduled, and disabled states (#297).
/// Set `RECORD_SNAPSHOTS=YES` to record or refresh baselines on macOS 26+.
@Suite("Compose Later action snapshots")
@MainActor
struct ComposeLaterSnapshotTests {
    @Test("compose Later button renders enabled, scheduled, and disabled beside Send", arguments: ["light", "dark"])
    func composeLaterStates(_ mode: String) {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let view = VStack(alignment: .leading, spacing: BrevSpacing.md) {
            stateRow(isScheduled: false, isEnabled: true, theme: theme)
            stateRow(isScheduled: true, isEnabled: true, theme: theme)
            stateRow(isScheduled: false, isEnabled: false, theme: theme)
        }
        .padding(BrevSpacing.md)
        .frame(width: 240, height: 156, alignment: .leading)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))

        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        host.view.frame = CGRect(x: 0, y: 0, width: 240, height: 156)
        host.view.needsLayout = true
        host.view.layoutSubtreeIfNeeded()
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 240, height: 156)),
            named: "compose-later-states-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }

    private func stateRow(isScheduled: Bool, isEnabled: Bool, theme: BrevTheme) -> some View {
        HStack(spacing: BrevSpacing.sm) {
            Image(systemName: "paperplane.fill")
                .foregroundStyle(theme.bgPrimary.color)
                .frame(width: 28, height: 28)
                .background(Circle().fill(theme.accent.color))
                .accessibilityHidden(true)
            ComposeLaterButtonView(
                isScheduled: isScheduled,
                isEnabled: isEnabled,
                hitTargetSize: 28,
                action: {}
            )
            Spacer(minLength: 0)
        }
    }
}
#endif
