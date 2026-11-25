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

/// macOS snapshot coverage for `ComposeSecurityWarningBanner` when an encrypted
/// or signed draft is switched onto a backend that does not support outbound
/// S/MIME (never silently downgrading to plaintext).
/// Set `RECORD_SNAPSHOTS=YES` to record or refresh baselines on macOS 26+.
@Suite("Compose security warning snapshots")
@MainActor
struct ComposeSecurityWarningSnapshotTests {
    @Test("unsupported-backend S/MIME warning banner renders clearly", arguments: ["light", "dark"])
    func unsupportedBackendWarningBanner(_ mode: String) {
        let theme = mode == "dark" ? BrevTheme.brevMonoDark : .brevMonoLight
        let warning = ComposeSecurityPresentation.unsupportedBackendWarning(
            isSigningEnabled: true,
            isEncryptionEnabled: true,
            supportsOutboundSMIME: false
        )
        #expect(warning != nil)

        let view = VStack(spacing: 0) {
            Spacer(minLength: 0)
            ComposeSecurityWarningBanner(
                isSigningEnabled: true,
                isEncryptionEnabled: true,
                supportsOutboundSMIME: false
            )
        }
        .frame(width: 560, height: 84, alignment: .bottom)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .environment(\.colorScheme, theme.mode.colorScheme)
        .environment(\.locale, Locale(identifier: "en_US"))

        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: 560, height: 84)),
            named: "compose-security-unsupported-backend-" + mode,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "YES" ? .all : nil
        )
    }
}
#endif
