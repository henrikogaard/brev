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

@testable import BrevMail
import BrevSettings
import BrevThemes
import Foundation
import SwiftUI
import Testing

@Suite("Sheet appearance")
struct SheetAppearanceTests {
    private func settings(mode: AppearanceThemeMode) throws -> AppearanceThemeSettings {
        let json = Data(#"{"mode":"\#(mode.rawValue)"}"#.utf8)
        return try JSONDecoder().decode(AppearanceThemeSettings.self, from: json)
    }

    @Test("follow-system leaves the scheme unpinned and tracks the sheet's own scheme")
    func followSystemTracksSheetScheme() throws {
        let light = try BrevSheetAppearanceResolution.resolve(
            presenterTheme: .brevMonoDark,
            settings: settings(mode: .followSystem),
            prefersDark: false,
            increasedContrast: false
        )
        let dark = try BrevSheetAppearanceResolution.resolve(
            presenterTheme: .brevMonoLight,
            settings: settings(mode: .followSystem),
            prefersDark: true,
            increasedContrast: false
        )

        #expect(light.preferredColorScheme == nil)
        #expect(light.theme.mode == .light)
        #expect(dark.preferredColorScheme == nil)
        #expect(dark.theme.mode == .dark)
    }

    @Test("always-dark pins dark even when the sheet starts out in a light system scheme")
    func alwaysDarkPinsDarkOnLightSystem() throws {
        let resolved = try BrevSheetAppearanceResolution.resolve(
            presenterTheme: .brevMonoLight,
            settings: settings(mode: .alwaysDark),
            prefersDark: false,
            increasedContrast: false
        )

        #expect(resolved.theme.mode == .dark)
        #expect(resolved.preferredColorScheme == .dark)
    }

    @Test("always-light pins light on a dark system")
    func alwaysLightPinsLightOnDarkSystem() throws {
        let resolved = try BrevSheetAppearanceResolution.resolve(
            presenterTheme: .brevMonoDark,
            settings: settings(mode: .alwaysLight),
            prefersDark: true,
            increasedContrast: false
        )

        #expect(resolved.theme.mode == .light)
        #expect(resolved.preferredColorScheme == .light)
    }

    @Test("without saved appearance settings the presenter's theme is kept and pinned to its mode")
    func legacyThemeIsKept() {
        let resolved = BrevSheetAppearanceResolution.resolve(
            presenterTheme: .brevMonoDark,
            settings: nil,
            prefersDark: false,
            increasedContrast: false
        )

        #expect(resolved.theme == .brevMonoDark)
        #expect(resolved.preferredColorScheme == .dark)
    }

    @Test("no presented view pins its own colour scheme with brevTheme")
    func presentedViewsUseTheSharedSheetModifier() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BrevMail")
        // RootAppearance.swift defines the shared modifier; the detached
        // reader is a macOS window root rather than a presented sheet; the
        // login view keeps its macOS-only branch.
        let allowed: Set<String> = ["RootAppearance.swift", "DetachedMessageWindow.swift", "LoginView.swift"]
        let files = try #require(FileManager.default.enumerator(atPath: sources.path))
        var scanned = 0
        var offenders: [String] = []
        for case let path as String in files where path.hasSuffix(".swift") {
            let name = URL(fileURLWithPath: path).lastPathComponent
            guard !allowed.contains(name) else { continue }
            scanned += 1
            let text = try String(contentsOf: sources.appendingPathComponent(path), encoding: .utf8)
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }
                if trimmed.contains(".brevTheme(") || trimmed.hasPrefix("brevTheme(") {
                    offenders.append("\(path):\(index + 1)")
                }
            }
        }
        #expect(scanned > 50, "The source scan found too few files; the path moved")
        #expect(offenders.isEmpty, "Use .brevSheetAppearance(_:) on presented views: \(offenders)")
    }
}
