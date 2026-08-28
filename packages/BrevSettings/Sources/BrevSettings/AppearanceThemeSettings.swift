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

import BrevThemes
import Foundation

public enum AppearanceThemeMode: String, CaseIterable, Identifiable, Sendable {
    case followSystem
    case alwaysLight
    case alwaysDark

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .followSystem: return String(localized: "System", bundle: .module)
        case .alwaysLight: return String(localized: "Light", bundle: .module)
        case .alwaysDark: return String(localized: "Dark", bundle: .module)
        }
    }

    var subtitle: String {
        switch self {
        case .followSystem: return String(localized: "Use the saved light and dark pair.", bundle: .module)
        case .alwaysLight: return String(localized: "Always use the selected light theme.", bundle: .module)
        case .alwaysDark: return String(localized: "Always use the selected dark theme.", bundle: .module)
        }
    }
}

public struct AppearanceThemeSettings: Equatable, Sendable {
    enum Key {
        static let mode = "appearance.themeMode"
        static let lightThemeID = "appearance.lightThemeID"
        static let darkThemeID = "appearance.darkThemeID"
        static let accentHex = "appearance.accentHex"
    }

    var mode: AppearanceThemeMode
    var lightThemeID: String
    var darkThemeID: String
    var accentHex: String?

    public static let defaults = AppearanceThemeSettings(
        mode: .followSystem,
        lightThemeID: "brev-mono-light",
        darkThemeID: "brev-mono-dark",
        accentHex: nil
    )

    /// Whether the app should inherit the operating system's active color
    /// scheme instead of pinning one of the saved theme modes.
    public var followsSystemAppearance: Bool {
        mode == .followSystem
    }

    public static func load(from defaults: UserDefaults = .standard) -> AppearanceThemeSettings {
        AppearanceThemeSettings(
            mode: enumValue(
                AppearanceThemeMode.self,
                for: Key.mode,
                defaultValue: Self.defaults.mode,
                defaults: defaults
            ),
            lightThemeID: nonEmptyString(
                for: Key.lightThemeID,
                defaultValue: Self.defaults.lightThemeID,
                defaults: defaults
            ),
            darkThemeID: nonEmptyString(
                for: Key.darkThemeID,
                defaultValue: Self.defaults.darkThemeID,
                defaults: defaults
            ),
            accentHex: normalizedAccentHex(defaults.string(forKey: Key.accentHex))
        )
    }

    public static func hasSavedValue(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: Key.mode) != nil
            || defaults.object(forKey: Key.lightThemeID) != nil
            || defaults.object(forKey: Key.darkThemeID) != nil
            || defaults.object(forKey: Key.accentHex) != nil
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: Key.mode)
        defaults.set(lightThemeID, forKey: Key.lightThemeID)
        defaults.set(darkThemeID, forKey: Key.darkThemeID)
        if let accentHex = Self.normalizedAccentHex(accentHex) {
            defaults.set(accentHex, forKey: Key.accentHex)
        } else {
            defaults.removeObject(forKey: Key.accentHex)
        }
    }

    func resolvedThemeID(prefersDark: Bool) -> String {
        switch mode {
        case .followSystem:
            return prefersDark ? darkThemeID : lightThemeID
        case .alwaysLight:
            return lightThemeID
        case .alwaysDark:
            return darkThemeID
        }
    }

    public func resolvedTheme(
        in builtIns: [BrevTheme] = BrevTheme.brevBuiltIns,
        prefersDark: Bool
    ) -> BrevTheme {
        let expectedMode: BrevThemeMode = resolvedThemeMode(prefersDark: prefersDark)
        let theme = selectedTheme(for: expectedMode, in: builtIns)

        guard let accentHex = Self.normalizedAccentHex(accentHex) else {
            return theme
        }
        return theme.withAccent(BrevColor(accentHex))
    }

    mutating func selectTheme(_ theme: BrevTheme) {
        switch theme.mode {
        case .light:
            lightThemeID = theme.id
        case .dark:
            darkThemeID = theme.id
        }
    }

    func selectedTheme(
        for mode: BrevThemeMode,
        in builtIns: [BrevTheme] = BrevTheme.brevBuiltIns
    ) -> BrevTheme {
        let selectedID = mode == .dark ? darkThemeID : lightThemeID
        return Self.theme(withID: selectedID, expectedMode: mode, in: builtIns)
            ?? fallbackTheme(for: mode, in: builtIns)
    }

    func resolvedThemeMode(prefersDark: Bool) -> BrevThemeMode {
        switch mode {
        case .followSystem:
            return prefersDark ? .dark : .light
        case .alwaysLight:
            return .light
        case .alwaysDark:
            return .dark
        }
    }

    private func fallbackTheme(
        for mode: BrevThemeMode,
        in builtIns: [BrevTheme]
    ) -> BrevTheme {
        let defaultID = mode == .dark ? Self.defaults.darkThemeID : Self.defaults.lightThemeID
        return Self.theme(withID: defaultID, expectedMode: mode, in: builtIns)
            ?? builtIns.first { $0.mode == mode }
            ?? .brevMonoLight
    }

    private static func theme(
        withID id: String,
        expectedMode: BrevThemeMode,
        in builtIns: [BrevTheme]
    ) -> BrevTheme? {
        builtIns.first { $0.id == id && $0.mode == expectedMode }
    }

    private static func normalizedAccentHex(_ value: String?) -> String? {
        guard let value else { return nil }
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.hasPrefix("#") {
            normalized.insert("#", at: normalized.startIndex)
        }
        let digits = normalized.dropFirst()
        guard digits.count == 6,
              digits.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        return normalized.uppercased()
    }

    private static func enumValue<Value>(
        _ type: Value.Type,
        for key: String,
        defaultValue: Value,
        defaults: UserDefaults
    ) -> Value where Value: RawRepresentable, Value.RawValue == String {
        guard let rawValue = defaults.string(forKey: key),
              let value = Value(rawValue: rawValue) else {
            return defaultValue
        }
        return value
    }

    private static func nonEmptyString(
        for key: String,
        defaultValue: String,
        defaults: UserDefaults
    ) -> String {
        guard let value = defaults.string(forKey: key),
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultValue
        }
        return value
    }
}
