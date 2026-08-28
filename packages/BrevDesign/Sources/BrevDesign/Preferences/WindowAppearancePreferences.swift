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

import Foundation

public enum WindowAppearancePreferenceKey {
    public static let mode = "window.translucencyMode"
    public static let scope = "window.translucencyScope"
    public static let surfaceOpacity = "window.surfaceOpacity"
    public static let sidebarOpacity = "window.sidebarOpacity"
    public static let messageContentOpacityMode = "window.messageContentOpacityMode"
    public static let messageContentOpacity = "window.messageContentOpacity"
}

public enum WindowTranslucencyMode: String, Sendable, Hashable, CaseIterable, Identifiable {
    case solid
    case subtle
    case frosted
    case glass

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .solid: return String(localized: "Solid", bundle: .module)
        case .subtle: return String(localized: "Subtle", bundle: .module)
        case .frosted: return String(localized: "Frosted", bundle: .module)
        case .glass: return String(localized: "Glass", bundle: .module)
        }
    }

    public var subtitle: String {
        switch self {
        case .solid: return String(localized: "Opaque surfaces for maximum readability.", bundle: .module)
        case .subtle: return String(localized: "Light system material for chrome and sidebars.", bundle: .module)
        case .frosted: return String(localized: "Stronger blur while reading panes use a themed layer.", bundle: .module)
        case .glass: return String(localized: "Liquid Glass where available, with readable fallback.", bundle: .module)
        }
    }

    public var usesTranslucency: Bool {
        self != .solid
    }
}

public enum WindowTranslucencyScope: String, Sendable, Hashable, CaseIterable, Identifiable {
    case sidebarOnly
    case mainWindow
    case allWindows

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sidebarOnly: return String(localized: "Sidebar", bundle: .module)
        case .mainWindow: return String(localized: "Main window", bundle: .module)
        case .allWindows: return String(localized: "All windows", bundle: .module)
        }
    }

    public var subtitle: String {
        switch self {
        case .sidebarOnly: return String(localized: "Only the folder sidebar uses translucency.", bundle: .module)
        case .mainWindow: return String(localized: "Mail and Settings windows use translucency.", bundle: .module)
        case .allWindows: return String(localized: "Mail, settings, and secondary windows use translucency.", bundle: .module)
        }
    }
}

/// Controls how the bounded message-reader surface derives its opacity.
public enum MessageContentOpacityMode: String, Sendable, Hashable, CaseIterable, Identifiable {
    case followPane
    case opaque
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .followPane: return String(localized: "Follow pane", bundle: .module)
        case .opaque: return String(localized: "No transparency", bundle: .module)
        case .custom: return String(localized: "Custom", bundle: .module)
        }
    }

    public var subtitle: String {
        switch self {
        case .followPane:
            return String(localized: "Uses the pane opacity, matching Brev's default appearance.", bundle: .module)
        case .opaque:
            return String(localized: "Keeps the surface behind message content fully opaque.", bundle: .module)
        case .custom:
            return String(localized: "Adjusts message readability without changing other panes.", bundle: .module)
        }
    }
}

public enum WindowSurfaceRole: Sendable, Hashable, CaseIterable {
    case mainWindow
    case sidebar
    case content
    case messageContent
    case settings
    case utility
    case card
}

public struct WindowAppearancePreferences: Equatable, Sendable {
    public static let surfaceOpacityRange: ClosedRange<Double> = 0.25 ... 0.95
    public static let sidebarOpacityRange: ClosedRange<Double> = 0.1 ... 0.95
    public static let messageContentOpacityRange: ClosedRange<Double> = 0.25 ... 1
    public static let defaultSurfaceOpacity = 0.82
    public static let defaultSidebarOpacity = 0.59

    public var mode: WindowTranslucencyMode
    public var scope: WindowTranslucencyScope
    public var surfaceOpacity: Double
    public var sidebarOpacity: Double
    public var messageContentOpacityMode: MessageContentOpacityMode
    public var messageContentOpacity: Double

    public init(
        mode: WindowTranslucencyMode,
        scope: WindowTranslucencyScope,
        surfaceOpacity: Double = Self.defaultSurfaceOpacity,
        sidebarOpacity: Double? = nil,
        messageContentOpacityMode: MessageContentOpacityMode = .followPane,
        messageContentOpacity: Double? = nil
    ) {
        self.mode = mode
        self.scope = scope
        let clampedSurfaceOpacity = Self.clampSurfaceOpacity(surfaceOpacity)
        self.surfaceOpacity = clampedSurfaceOpacity
        self.sidebarOpacity = Self.clampSidebarOpacity(
            sidebarOpacity ?? Self.sidebarOpacityDefault(for: clampedSurfaceOpacity)
        )
        self.messageContentOpacityMode = messageContentOpacityMode
        self.messageContentOpacity = Self.clampMessageContentOpacity(
            messageContentOpacity ?? clampedSurfaceOpacity
        )
    }

    public static let defaults = WindowAppearancePreferences(
        mode: .solid,
        scope: .mainWindow,
        surfaceOpacity: Self.defaultSurfaceOpacity,
        sidebarOpacity: Self.defaultSidebarOpacity
    )

    public static func load(from defaults: UserDefaults = .standard) -> WindowAppearancePreferences {
        let surfaceOpacity = doubleValue(
            for: WindowAppearancePreferenceKey.surfaceOpacity,
            defaultValue: Self.defaults.surfaceOpacity,
            defaults: defaults,
            clamp: clampSurfaceOpacity
        )
        let sidebarOpacity = optionalDoubleValue(
            for: WindowAppearancePreferenceKey.sidebarOpacity,
            defaults: defaults,
            clamp: clampSidebarOpacity
        )

        return WindowAppearancePreferences(
            mode: enumValue(
                WindowTranslucencyMode.self,
                for: WindowAppearancePreferenceKey.mode,
                defaultValue: Self.defaults.mode,
                defaults: defaults
            ),
            scope: enumValue(
                WindowTranslucencyScope.self,
                for: WindowAppearancePreferenceKey.scope,
                defaultValue: Self.defaults.scope,
                defaults: defaults
            ),
            surfaceOpacity: surfaceOpacity,
            sidebarOpacity: sidebarOpacity,
            messageContentOpacityMode: enumValue(
                MessageContentOpacityMode.self,
                for: WindowAppearancePreferenceKey.messageContentOpacityMode,
                defaultValue: .followPane,
                defaults: defaults
            ),
            messageContentOpacity: optionalDoubleValue(
                for: WindowAppearancePreferenceKey.messageContentOpacity,
                defaults: defaults,
                clamp: clampMessageContentOpacity
            )
        )
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: WindowAppearancePreferenceKey.mode)
        defaults.set(scope.rawValue, forKey: WindowAppearancePreferenceKey.scope)
        defaults.set(surfaceOpacity, forKey: WindowAppearancePreferenceKey.surfaceOpacity)
        defaults.set(sidebarOpacity, forKey: WindowAppearancePreferenceKey.sidebarOpacity)
        defaults.set(messageContentOpacityMode.rawValue, forKey: WindowAppearancePreferenceKey.messageContentOpacityMode)
        defaults.set(messageContentOpacity, forKey: WindowAppearancePreferenceKey.messageContentOpacity)
    }

    public func effectiveMode(reduceTransparency: Bool) -> WindowTranslucencyMode {
        reduceTransparency ? .solid : mode
    }

    public func usesMaterial(
        for role: WindowSurfaceRole,
        reduceTransparency: Bool
    ) -> Bool {
        effectiveMode(reduceTransparency: reduceTransparency).usesTranslucency
            && scope.applies(to: role)
            && role.supportsLiveMaterial
    }

    public func usesSurfaceOpacity(
        for role: WindowSurfaceRole,
        reduceTransparency: Bool
    ) -> Bool {
        // Window-container roles host the shared material. Their child sidebar
        // and content roles own the single themed readability layer.
        guard role != .mainWindow, role != .settings else { return false }
        return effectiveMode(reduceTransparency: reduceTransparency).usesTranslucency
            && scope.applies(to: role)
    }

    public func surfaceFillOpacity(
        for role: WindowSurfaceRole,
        reduceTransparency: Bool
    ) -> Double? {
        guard effectiveMode(reduceTransparency: reduceTransparency).usesTranslucency else {
            return 1
        }
        guard scope.applies(to: role) else { return 1 }
        // Avoid compounding the pane opacity underneath every child surface.
        guard role != .mainWindow, role != .settings else { return nil }
        guard role != .sidebar else { return sidebarOpacity }
        guard role != .messageContent else {
            return switch messageContentOpacityMode {
            case .followPane: surfaceOpacity
            case .opaque: 1
            case .custom: messageContentOpacity
            }
        }
        return surfaceOpacity
    }

    public func windowBackgroundAlpha(
        for role: WindowSurfaceRole,
        reduceTransparency: Bool
    ) -> Double {
        usesTransparentWindowChrome(for: role, reduceTransparency: reduceTransparency) ? 0 : 1
    }

    public func usesTransparentWindowChrome(
        for role: WindowSurfaceRole,
        reduceTransparency: Bool
    ) -> Bool {
        guard effectiveMode(reduceTransparency: reduceTransparency).usesTranslucency else {
            return false
        }

        switch role {
        case .mainWindow:
            return true
        case .settings:
            // Settings chrome clears whenever Main window or All windows scope
            // applies — matching `applies(to: .settings)`.
            return scope == .mainWindow || scope == .allWindows
        case .utility:
            return scope == .allWindows
        case .sidebar, .content, .messageContent, .card:
            return scope.applies(to: role)
        }
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

    private static func doubleValue(
        for key: String,
        defaultValue: Double,
        defaults: UserDefaults,
        clamp: (Double) -> Double
    ) -> Double {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return clamp(defaults.double(forKey: key))
    }

    private static func optionalDoubleValue(
        for key: String,
        defaults: UserDefaults,
        clamp: (Double) -> Double
    ) -> Double? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return clamp(defaults.double(forKey: key))
    }

    private static func clampSurfaceOpacity(_ value: Double) -> Double {
        min(max(value, surfaceOpacityRange.lowerBound), surfaceOpacityRange.upperBound)
    }

    private static func clampSidebarOpacity(_ value: Double) -> Double {
        min(max(value, sidebarOpacityRange.lowerBound), sidebarOpacityRange.upperBound)
    }

    private static func clampMessageContentOpacity(_ value: Double) -> Double {
        min(max(value, messageContentOpacityRange.lowerBound), messageContentOpacityRange.upperBound)
    }

    private static func sidebarOpacityDefault(for surfaceOpacity: Double) -> Double {
        let rawValue = surfaceOpacity * 0.72
        let roundedValue = (rawValue * 100).rounded() / 100
        return Self.clampSidebarOpacity(roundedValue)
    }
}

public extension WindowTranslucencyScope {
    func applies(to role: WindowSurfaceRole) -> Bool {
        switch self {
        case .sidebarOnly:
            return role == .sidebar
        case .mainWindow:
            switch role {
            case .mainWindow, .sidebar, .content, .messageContent, .card, .utility, .settings:
                // Settings follows Main window so Appearance → Window design is
                // visible without requiring All windows. Auxiliary utility
                // windows (e.g. compose) also follow the main window.
                return true
            }
        case .allWindows:
            return true
        }
    }
}

private extension WindowSurfaceRole {
    var supportsLiveMaterial: Bool {
        switch self {
        case .mainWindow, .sidebar, .settings, .utility:
            return true
        case .content, .messageContent, .card:
            return false
        }
    }
}
