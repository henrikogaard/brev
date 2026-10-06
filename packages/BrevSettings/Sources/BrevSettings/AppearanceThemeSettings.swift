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
#if os(macOS)
import AppKit
#endif

public extension Notification.Name {
    /// Posted when `AppearanceThemeSettings.save(to:)` persists a change so
    /// cached copies (root appearance, settings panes) reload once instead
    /// of re-reading defaults on every view evaluation.
    static let brevAppearanceThemeSettingsDidChange = Notification.Name(
        "eu.brevmail.settings.appearanceTheme.changed"
    )
}

/// The source used to choose the application's effective accent color.
public enum AppearanceAccentSource: String, CaseIterable, Identifiable, Sendable, Codable {
    case theme
    case system
    case custom

    public var id: String { rawValue }

    /// Localized label suitable for an appearance source picker.
    public var title: String {
        switch self {
        case .theme:
            return String(localized: "Theme", bundle: .module)
        case .system:
            return String(localized: "System accent", bundle: .module)
        case .custom:
            return String(localized: "Custom", bundle: .module)
        }
    }

    /// Sources supported by the current platform's appearance controls.
    public static var availableSources: [AppearanceAccentSource] {
        #if os(iOS)
        return [.theme, .custom]
        #else
        return [.theme, .system, .custom]
        #endif
    }
}

public enum AppearanceThemeMode: String, CaseIterable, Identifiable, Sendable, Codable {
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

public struct AppearanceThemeSettings: Equatable, Sendable, Codable {
    enum Key {
        static let mode = "appearance.themeMode"
        static let lightThemeID = "appearance.lightThemeID"
        static let darkThemeID = "appearance.darkThemeID"
        static let accentHex = "appearance.accentHex"
        static let accentSource = "appearance.accentSource"
    }

    var mode: AppearanceThemeMode
    var lightThemeID: String
    var darkThemeID: String
    var accentHex: String?
    var accentSource: AppearanceAccentSource

    private enum CodingKeys: String, CodingKey {
        case mode
        case lightThemeID
        case darkThemeID
        case accentHex
        case accentSource
    }

    init(
        mode: AppearanceThemeMode,
        lightThemeID: String,
        darkThemeID: String,
        accentHex: String? = nil,
        accentSource: AppearanceAccentSource = .theme
    ) {
        self.mode = mode
        self.lightThemeID = lightThemeID
        self.darkThemeID = darkThemeID
        self.accentHex = accentHex
        self.accentSource = accentSource
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let accentHex = Self.normalizedAccentHex(
            (try? container.decodeIfPresent(String.self, forKey: .accentHex)) ?? nil
        )
        let source = ((try? container.decodeIfPresent(String.self, forKey: .accentSource)) ?? nil)
            .flatMap(AppearanceAccentSource.init(rawValue:))
            ?? (accentHex == nil ? .theme : .custom)
        try self.init(
            mode: container.decodeIfPresent(AppearanceThemeMode.self, forKey: .mode)
                ?? Self.defaults.mode,
            lightThemeID: container.decodeIfPresent(String.self, forKey: .lightThemeID)
                ?? Self.defaults.lightThemeID,
            darkThemeID: container.decodeIfPresent(String.self, forKey: .darkThemeID)
                ?? Self.defaults.darkThemeID,
            accentHex: accentHex,
            accentSource: source
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(lightThemeID, forKey: .lightThemeID)
        try container.encode(darkThemeID, forKey: .darkThemeID)
        try container.encodeIfPresent(Self.normalizedAccentHex(accentHex), forKey: .accentHex)
        try container.encode(accentSource, forKey: .accentSource)
    }

    public static let defaults = AppearanceThemeSettings(
        mode: .followSystem,
        lightThemeID: "brev-mono-light",
        darkThemeID: "brev-mono-grey",
        accentHex: nil,
        accentSource: .theme
    )

    /// Whether the app should inherit the operating system's active color
    /// scheme instead of pinning one of the saved theme modes.
    public var followsSystemAppearance: Bool {
        mode == .followSystem
    }

    public static func load(from defaults: UserDefaults = .standard) -> AppearanceThemeSettings {
        let accentHex = normalizedAccentHex(defaults.string(forKey: Key.accentHex))
        return AppearanceThemeSettings(
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
            accentHex: accentHex,
            accentSource: accentSource(
                defaults.string(forKey: Key.accentSource),
                accentHex: accentHex
            )
        )
    }

    public static func hasSavedValue(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: Key.mode) != nil
            || defaults.object(forKey: Key.lightThemeID) != nil
            || defaults.object(forKey: Key.darkThemeID) != nil
            || defaults.object(forKey: Key.accentHex) != nil
            || defaults.object(forKey: Key.accentSource) != nil
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
        defaults.set(accentSource.rawValue, forKey: Key.accentSource)
        NotificationCenter.default.post(name: .brevAppearanceThemeSettingsDidChange, object: nil)
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
        prefersDark: Bool,
        systemAccent: BrevColor? = nil,
        increasedContrast: Bool = false
    ) -> BrevTheme {
        let expectedMode: BrevThemeMode = resolvedThemeMode(prefersDark: prefersDark)
        let theme = selectedTheme(for: expectedMode, in: builtIns)

        let requestedAccent: BrevColor?
        switch accentSource {
        case .theme:
            requestedAccent = nil
        case .custom:
            requestedAccent = Self.normalizedAccentHex(accentHex).map(BrevColor.init)
        case .system:
            #if os(macOS)
            requestedAccent = systemAccent
                ?? Self.macOSSystemAccent(for: expectedMode)
            #else
            requestedAccent = nil
            #endif
        }

        guard let requestedAccent else {
            return theme
        }
        return theme
            .withAccent(requestedAccent)
            .withReadableAccent(increasedContrast: increasedContrast)
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

    private static func accentSource(
        _ rawValue: String?,
        accentHex: String?
    ) -> AppearanceAccentSource {
        guard let rawValue,
              let source = AppearanceAccentSource(rawValue: rawValue) else {
            return accentHex == nil ? .theme : .custom
        }
        return source
    }

    #if os(macOS)
    private static func macOSSystemAccent(for mode: BrevThemeMode) -> BrevColor? {
        guard let appearance = NSAppearance(
            named: mode == .dark ? .darkAqua : .aqua
        ) else {
            return nil
        }

        var color: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            color = NSColor.controlAccentColor.usingColorSpace(.sRGB)
        }
        guard let color else { return nil }
        return BrevColor(
            String(
                format: "#%02X%02X%02X",
                Int((color.redComponent * 255).rounded()),
                Int((color.greenComponent * 255).rounded()),
                Int((color.blueComponent * 255).rounded())
            )
        )
    }
    #endif

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
