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

@testable import BrevSettings
import SwiftUI
import Testing

@Suite("SettingsLayoutPolicy")
struct SettingsLayoutPolicyTests {
    @Test("phone compact horizontal size class uses stack navigation")
    func phoneCompactHorizontalSizeClassUsesStackNavigation() {
        #expect(SettingsLayoutPolicy.layout(
            for: .compact,
            device: .phone
        ) == .stack)
    }

    @Test("phone regular or unspecified size class uses split navigation")
    func phoneRegularOrUnspecifiedSizeClassUsesSplitNavigation() {
        #expect(SettingsLayoutPolicy.layout(
            for: .regular,
            device: .phone
        ) == .split)
        #expect(SettingsLayoutPolicy.layout(
            for: nil,
            device: .phone
        ) == .split)
    }

    @Test("iPad follows compact width instead of forcing a squeezed split")
    func iPadCompactWidthUsesStackNavigation() {
        #expect(SettingsLayoutPolicy.layout(
            for: .compact,
            device: .pad
        ) == .stack)
        #expect(SettingsLayoutPolicy.layout(
            for: .regular,
            device: .pad
        ) == .split)
    }

    @Test("desktop keeps split navigation")
    func desktopKeepsSplitNavigation() {
        #expect(SettingsLayoutPolicy.layout(
            for: .compact,
            device: .desktop
        ) == .split)
    }

    @Test("iOS settings sheets expose an explicit dismiss button")
    func iOSSettingsSheetsExposeExplicitDismissButton() {
        #expect(SettingsDismissButtonPolicy.showsDismissButton(device: .phone))
        #expect(SettingsDismissButtonPolicy.showsDismissButton(device: .pad))
        #expect(!SettingsDismissButtonPolicy.showsDismissButton(device: .desktop))
    }
}
