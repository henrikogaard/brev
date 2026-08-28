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

@testable import BrevPlugins
import SwiftUI
import Testing

// MARK: - Test plugin

@MainActor
private final class TestPlugin: BrevUIExtension {
    let identifier: String
    let displayName = "Test Plugin"
    let author = "Brev Tests"
    private(set) var viewedContributionIDs: [String] = []

    let contributions: [ContributionDefinition] = [
        ContributionDefinition(
            id: "test-toolbar",
            kind: UIExtensionContributionKind.composeToolbar,
            displayName: "Test Toolbar Action",
            sfSymbolName: "star"
        ),
        ContributionDefinition(
            id: "test-menu",
            kind: UIExtensionContributionKind.messageContextMenu,
            displayName: "Test Menu Action",
            sfSymbolName: "ellipsis"
        ),
        ContributionDefinition(
            id: "test-settings",
            kind: UIExtensionContributionKind.settingsPanel,
            displayName: "Test Settings",
            sfSymbolName: "gearshape"
        ),
        ContributionDefinition(
            id: "test-sidebar",
            kind: UIExtensionContributionKind.sidebarPanel,
            displayName: "Test Sidebar",
            sfSymbolName: "sidebar.left"
        )
    ]

    init(identifier: String = "com.brev.test-plugin") {
        self.identifier = identifier
    }

    func view(for contributionID: String) -> AnyView {
        viewedContributionIDs.append(contributionID)
        return AnyView(Text("Test: \(contributionID)"))
    }
}

// MARK: - Registry tests

@MainActor
struct BrevPluginRegistryTests {
    @Test("registry starts empty")
    func emptyInitially() {
        let registry = BrevPluginRegistry()
        #expect(registry.allExtensions.isEmpty)
    }

    @Test("registered plugin appears in allExtensions")
    func registerAddsPlugin() {
        let registry = BrevPluginRegistry()
        let plugin = TestPlugin()
        registry.register(plugin)
        #expect(registry.allExtensions.count == 1)
        #expect(registry.allExtensions.first?.identifier == "com.brev.test-plugin")
    }

    @Test("duplicate identifier replaces previous plugin")
    func duplicateReplaces() {
        let registry = BrevPluginRegistry()
        let first = TestPlugin()
        let second = TestPlugin()
        registry.register(first)
        registry.register(second)
        #expect(registry.allExtensions.count == 1)
    }

    @Test("contributions returns only matching kind")
    func contributionsFilterByKind() {
        let registry = BrevPluginRegistry()
        let plugin = TestPlugin()
        registry.register(plugin)

        let toolbar = registry.contributions(for: .composeToolbar)
        #expect(toolbar.count == 1)
        #expect(toolbar[0].id == "test-toolbar")
        #expect(toolbar[0].kind == UIExtensionContributionKind.composeToolbar)

        let menu = registry.contributions(for: .messageContextMenu)
        #expect(menu.count == 1)
        #expect(menu[0].id == "test-menu")
    }

    @Test("view(for:pluginID:) returns correct view")
    func viewForContribution() {
        let registry = BrevPluginRegistry()
        let plugin = TestPlugin()
        registry.register(plugin)

        let view = registry.view(for: "test-toolbar", pluginID: "com.brev.test-plugin")
        #expect(view != nil)

        let missing = registry.view(for: "nonexistent", pluginID: "com.brev.test-plugin")
        #expect(missing == nil)

        let noPlugin = registry.view(for: "test-toolbar", pluginID: "com.brev.unknown")
        #expect(noPlugin == nil)
    }

    @Test("view(for:) searches all plugins when pluginID is nil")
    func viewSearchesAllPlugins() {
        let registry = BrevPluginRegistry()
        let plugin = TestPlugin()
        registry.register(plugin)

        let view = registry.view(for: "test-toolbar")
        #expect(view != nil)
    }

    @Test("legacy lookup resolves duplicate IDs deterministically")
    func legacyLookupResolvesDuplicateIDsDeterministically() {
        let registry = BrevPluginRegistry()
        let later = TestPlugin(identifier: "com.brev.z-plugin")
        let earlier = TestPlugin(identifier: "com.brev.a-plugin")
        registry.register(later)
        registry.register(earlier)

        #expect(registry.view(for: "test-settings") != nil)
        #expect(earlier.viewedContributionIDs == ["test-settings"])
        #expect(later.viewedContributionIDs.isEmpty)
    }

    @Test("empty contributions for unregistered kind")
    func emptyContributions() {
        let registry = BrevPluginRegistry()
        _ = registry
        let empty = BrevPluginRegistry()
        #expect(empty.contributions(for: UIExtensionContributionKind.composeToolbar).isEmpty)
    }

    @Test("registered contributions are deterministic and namespaced")
    func registeredContributionsAreDeterministicAndNamespaced() {
        let registry = BrevPluginRegistry()
        let first = TestPlugin()
        let second = TestPlugin(identifier: "com.brev.other-plugin")
        registry.register(second)
        registry.register(first)

        let contributions = registry.registeredContributions(for: .settingsPanel)
        #expect(contributions.map(\.pluginID) == [
            "com.brev.other-plugin",
            "com.brev.test-plugin",
        ])
        #expect(contributions.map(\.id) == [
            "com.brev.other-plugin::test-settings",
            "com.brev.test-plugin::test-settings",
        ])
        #expect(registry.view(for: contributions[0]) != nil)
    }
}

// MARK: - ContributionDefinition tests

struct ContributionDefinitionTests {
    @Test("definition equality uses all stored properties")
    func equalityByValue() {
        let a = ContributionDefinition(
            id: "x", kind: .composeToolbar, displayName: "A", sfSymbolName: "star"
        )
        let b = ContributionDefinition(
            id: "x", kind: .composeToolbar, displayName: "A", sfSymbolName: "star"
        )
        let c = ContributionDefinition(
            id: "y", kind: .composeToolbar, displayName: "A", sfSymbolName: "star"
        )
        #expect(a == b)
        #expect(a != c)
    }

    @Test("four contribution kinds exist")
    func fourKinds() {
        #expect(UIExtensionContributionKind.allCases.count == 4)
        #expect(UIExtensionContributionKind.allCases.contains(.composeToolbar))
        #expect(UIExtensionContributionKind.allCases.contains(.messageContextMenu))
        #expect(UIExtensionContributionKind.allCases.contains(.settingsPanel))
        #expect(UIExtensionContributionKind.allCases.contains(.sidebarPanel))
    }
}

// MARK: - Sendable conformance tests

struct SendableTests {
    @Test("ContributionDefinition is Sendable")
    func contributionIsSendable() {
        let _: @Sendable () -> Void = {
            let d = ContributionDefinition(
                id: "t", kind: .composeToolbar, displayName: "T", sfSymbolName: "t"
            )
            _ = d
        }
    }

    @Test("UIExtensionContributionKind is Sendable")
    func kindIsSendable() {
        let _: @Sendable () -> Void = {
            _ = UIExtensionContributionKind.composeToolbar
        }
    }
}
