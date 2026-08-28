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

public struct DeveloperSettings: Codable, Equatable, Sendable {
    enum Key {
        static let demoModeEnabled = "developer.demoModeEnabled"
    }

    public var demoModeEnabled: Bool

    public static let defaults = DeveloperSettings(demoModeEnabled: false)

    public init(demoModeEnabled: Bool = false) {
        self.demoModeEnabled = demoModeEnabled
    }

    public static func load(from defaults: UserDefaults = .standard) -> DeveloperSettings {
        DeveloperSettings(
            demoModeEnabled: defaults.object(forKey: Key.demoModeEnabled) != nil
                ? defaults.bool(forKey: Key.demoModeEnabled)
                : Self.defaults.demoModeEnabled
        )
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(demoModeEnabled, forKey: Key.demoModeEnabled)
    }

    public static func isDemoModeRequested(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard,
        isDeveloperBuild: Bool
    ) -> Bool {
        guard isDeveloperBuild else { return false }
        if let override = environment["BREV_USE_MOCK"] {
            return booleanEnvironmentValue(override)
        }
        return load(from: defaults).demoModeEnabled
    }

    private static func booleanEnvironmentValue(_ value: String) -> Bool {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }
}

public struct DeveloperSettingsActions {
    let applyDemoMode: @MainActor (Bool) async -> Void

    public init(
        applyDemoMode: @escaping @MainActor (Bool) async -> Void = { _ in }
    ) {
        self.applyDemoMode = applyDemoMode
    }

    public static let unavailable = DeveloperSettingsActions()
}
