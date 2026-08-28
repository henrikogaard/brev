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
import SwiftUI

/// The central registry for Brev UI extensions.
///
/// Plugins register themselves during app initialisation; the host app
/// reads contributions at chrome-render time. Because all interaction
/// is `@MainActor` (SwiftUI views), the registry uses main-actor
/// isolation rather than a separate actor.
///
/// Contributions are enumerated in stable identifier order rather than
/// dictionary or registration order. Every plugin must be registered before
/// the relevant chrome is rendered.
@MainActor
public final class BrevPluginRegistry {
    /// Shared app-wide registry.
    public static let shared = BrevPluginRegistry()

    private var plugins: [String: any BrevUIExtension] = [:]

    /// Create a fresh registry. Use `BrevPluginRegistry.shared` or
    /// create a separate instance for testing.
    public init() {}

    /// Register a plugin instance. Replaces any previous plugin with
    /// the same `identifier`.
    public func register(_ plugin: any BrevUIExtension) {
        plugins[plugin.identifier] = plugin
    }

    /// All contributions of a given kind, collected from every
    /// registered plugin in deterministic identifier order.
    public func contributions(for kind: UIExtensionContributionKind) -> [ContributionDefinition] {
        registeredContributions(for: kind).map(\.definition)
    }

    /// All contributions of a given kind paired with their owning plugin.
    ///
    /// The returned `id` is namespaced by plugin identifier, so host views can
    /// safely render contributions from multiple plugins that chose the same
    /// plugin-local declaration ID.
    public func registeredContributions(
        for kind: UIExtensionContributionKind
    ) -> [RegisteredContribution] {
        plugins.values
            .sorted { $0.identifier < $1.identifier }
            .flatMap { plugin in
                plugin.contributions
                    .filter { $0.kind == kind }
                    .sorted { lhs, rhs in
                        if lhs.id != rhs.id { return lhs.id < rhs.id }
                        return lhs.displayName < rhs.displayName
                    }
                    .map { RegisteredContribution(pluginID: plugin.identifier, definition: $0) }
            }
    }

    /// All registered extension instances (for enumeration / UI).
    public var allExtensions: [any BrevUIExtension] {
        plugins.values.sorted { $0.identifier < $1.identifier }
    }

    /// Returns the view associated with a namespaced contribution identity.
    public func view(for contribution: RegisteredContribution) -> AnyView? {
        view(for: contribution.definition.id, pluginID: contribution.pluginID)
    }

    /// Returns the view for a specific contribution.
    /// - Parameters:
    ///   - contributionID: The `ContributionDefinition.id` to look up.
    ///   - pluginID: Optional filter; only search the plugin with this
    ///     `identifier`. When `nil`, searches all plugins.
    /// When `pluginID` is omitted, duplicate plugin-local IDs resolve to the
    /// lexicographically first plugin identifier. Hosts that need to preserve
    /// both contributions should use `RegisteredContribution` instead.
    /// - Returns: The view, or `nil` if no matching contribution is found.
    public func view(
        for contributionID: String,
        pluginID: String? = nil
    ) -> AnyView? {
        let candidates = pluginID.flatMap { id in
            plugins.values.filter { $0.identifier == id }
        } ?? plugins.values.sorted { $0.identifier < $1.identifier }

        for plugin in candidates {
            if plugin.contributions.contains(where: { $0.id == contributionID }) {
                return plugin.view(for: contributionID)
            }
        }
        return nil
    }
}
