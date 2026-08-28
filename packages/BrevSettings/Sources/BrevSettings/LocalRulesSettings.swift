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

import BrevBackend
import Foundation

public extension Notification.Name {
    /// Posted after local rules are written from outside the Settings screen
    /// (e.g. "Create Rule from Message"), so any open Settings → Rules view
    /// reloads its in-memory snapshot instead of clobbering it on its next write.
    static let brevLocalRulesDidChange = Notification.Name("brev.localRulesDidChange")
}

public struct LocalRulesSettings: Codable, Equatable, Sendable {
    public enum Key {
        public static let settings = "localRules.settings.v1"
        public static let isAutomaticExecutionEnabled = "localRules.isAutomaticExecutionEnabled.v1"
    }

    public var rules: [ServerRule]
    public var isAutomaticExecutionEnabled: Bool

    public static let defaults = LocalRulesSettings(
        rules: [],
        isAutomaticExecutionEnabled: false
    )

    public init(
        rules: [ServerRule],
        isAutomaticExecutionEnabled: Bool
    ) {
        self.rules = rules
        self.isAutomaticExecutionEnabled = isAutomaticExecutionEnabled
    }

    public static func load(from defaults: UserDefaults = .standard) -> LocalRulesSettings {
        if let data = defaults.data(forKey: Key.settings),
           let settings = try? JSONDecoder().decode(LocalRulesSettings.self, from: data) {
            return settings
        }

        // Backward compatibility for early ad-hoc toggles.
        if defaults.object(forKey: Key.isAutomaticExecutionEnabled) != nil {
            return LocalRulesSettings(
                rules: [],
                isAutomaticExecutionEnabled: defaults.bool(forKey: Key.isAutomaticExecutionEnabled)
            )
        }

        return .defaults
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Key.settings)
        defaults.set(isAutomaticExecutionEnabled, forKey: Key.isAutomaticExecutionEnabled)
    }

    public mutating func add(_ rule: ServerRule) {
        rules.append(rule)
    }

    public mutating func update(_ rule: ServerRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
    }

    public mutating func remove(id: ServerRule.ID) {
        rules.removeAll { $0.id == id }
    }

    public mutating func moveUp(id: ServerRule.ID) {
        guard let index = rules.firstIndex(where: { $0.id == id }),
              index > 0 else { return }
        rules.swapAt(index - 1, index)
    }

    public mutating func moveDown(id: ServerRule.ID) {
        guard let index = rules.firstIndex(where: { $0.id == id }),
              index < rules.index(before: rules.endIndex) else { return }
        rules.swapAt(index, index + 1)
    }

    public mutating func setEnabled(_ isEnabled: Bool, id: ServerRule.ID) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].isEnabled = isEnabled
    }
}
