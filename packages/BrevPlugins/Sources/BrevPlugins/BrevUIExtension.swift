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

import SwiftUI

/// A plugin that contributes UI surfaces to the Brev mail client.
///
/// Conform to this protocol in your SPM package, then register the
/// instance with `BrevPluginRegistry.shared.register(_:)` during
/// the app's initialisation phase.
///
/// Each plugin returns a list of `ContributionDefinition` values
/// that describe where the plugin's views appear. The actual
/// SwiftUI views are created on demand by `view(for:)`.
///
/// Plugin views receive the current `@Environment(\.brevTheme)`
/// automatically because they are rendered inside Brev's SwiftUI
/// hierarchy.
///
/// - Note: This protocol is `@MainActor` because view creation
///   must happen on the main actor.
@MainActor
public protocol BrevUIExtension: AnyObject {
    /// Stable reverse-domain identifier (e.g. `"com.example.my-plugin"`).
    var identifier: String { get }

    /// Human-readable name shown in plugin-management UI.
    var displayName: String { get }

    /// Who created this plugin.
    var author: String { get }

    /// The UI surfaces this plugin contributes.
    var contributions: [ContributionDefinition] { get }

    /// Return the SwiftUI view for a given contribution definition.
    ///
    /// - Parameter contributionID: The `id` from one of the entries
    ///   in `contributions`.
    /// - Returns: A type-erased view for rendering.
    func view(for contributionID: String) -> AnyView
}
