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
@testable import BrevSettings
import Foundation
import Testing

@Suite("LocalRulesSettings")
struct LocalRulesSettingsTests {
    @Test("defaults are disabled with no rules")
    func defaultsAreDisabledWithNoRules() {
        #expect(LocalRulesSettings.defaults.rules.isEmpty)
        #expect(LocalRulesSettings.defaults.isAutomaticExecutionEnabled == false)
    }

    @Test("settings persist rules and automatic toggle")
    func settingsPersistRulesAndAutomaticToggle() throws {
        let defaults = try makeDefaults()
        var settings = LocalRulesSettings.defaults
        settings.isAutomaticExecutionEnabled = true
        settings.add(Self.rule(id: "rule-1", name: "Flag invoices", action: .flag))
        settings.save(to: defaults)

        let restored = LocalRulesSettings.load(from: defaults)
        #expect(restored == settings)
    }

    @Test("crud and ordering helpers mutate deterministic order")
    func crudAndOrderingHelpersMutateDeterministicOrder() {
        var settings = LocalRulesSettings.defaults
        let first = Self.rule(id: "rule-1", name: "First", action: .markRead)
        let second = Self.rule(id: "rule-2", name: "Second", action: .flag)
        settings.add(first)
        settings.add(second)

        settings.moveUp(id: "rule-2")
        #expect(settings.rules.map(\.id) == ["rule-2", "rule-1"])

        settings.moveDown(id: "rule-2")
        #expect(settings.rules.map(\.id) == ["rule-1", "rule-2"])

        var updated = first
        updated.name = "Updated name"
        settings.update(updated)
        #expect(settings.rules.first?.name == "Updated name")

        settings.setEnabled(false, id: "rule-2")
        #expect(settings.rules.last?.isEnabled == false)

        settings.remove(id: "rule-1")
        #expect(settings.rules.map(\.id) == ["rule-2"])
    }

    private static func rule(id: String, name: String, action: ServerRuleAction) -> ServerRule {
        ServerRule(
            id: id,
            name: name,
            isEnabled: true,
            conditions: [.subjectContains("invoice")],
            actions: [action]
        )
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "LocalRulesSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
