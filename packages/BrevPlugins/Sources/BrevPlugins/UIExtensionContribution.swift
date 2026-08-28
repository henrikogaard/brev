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

/// The surface point in Brev's chrome where a plugin view can appear.
/// Each case corresponds to a specific UI location; the host app is
/// responsible for iterating plugin contributions and rendering them.
public enum UIExtensionContributionKind: String, CaseIterable, Hashable, Sendable {
    /// A button in the compose window's toolbar.
    /// The view should be a compact icon/label suitable for a toolbar.
    case composeToolbar

    /// An action in the message-list or message-detail context menu.
    /// The view is rendered as a `Button` or `Menu` item.
    case messageContextMenu

    /// A section in the Preferences / Settings window.
    /// The view occupies a full settings panel with scroll content.
    case settingsPanel

    /// An item in the sidebar's "Extensions" group.
    /// The view fills the main content area when selected.
    case sidebarPanel
}

/// Describes one UI surface a plugin contributes, without the view
/// itself. The view is retrieved via `BrevUIExtension.view(for:)`.
public struct ContributionDefinition: Identifiable, Hashable, Sendable {
    /// Stable identifier unique within the plugin's contribution list.
    public let id: String

    /// Where this contribution appears in Brev's chrome.
    public let kind: UIExtensionContributionKind

    /// Human-readable label (e.g. "Summarize thread").
    public let displayName: String

    /// SF Symbol name for the icon (e.g. "text.badge.star").
    public let sfSymbolName: String

    public init(
        id: String,
        kind: UIExtensionContributionKind,
        displayName: String,
        sfSymbolName: String
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.sfSymbolName = sfSymbolName
    }
}

/// A contribution paired with the plugin that owns it.
///
/// Contribution identifiers are only required to be unique within one
/// plugin's declaration. The registry therefore exposes this namespaced
/// identity to hosts so two plugins can safely use the same local ID.
public struct RegisteredContribution: Identifiable, Hashable, Sendable {
    /// The plugin's stable identifier.
    public let pluginID: String

    /// The plugin-local contribution declaration.
    public let definition: ContributionDefinition

    public init(pluginID: String, definition: ContributionDefinition) {
        self.pluginID = pluginID
        self.definition = definition
    }

    /// A deterministic, collision-safe identity for use in `ForEach` and
    /// selection state.
    public var id: String {
        "\(pluginID)::\(definition.id)"
    }

    public var kind: UIExtensionContributionKind { definition.kind }
    public var displayName: String { definition.displayName }
    public var sfSymbolName: String { definition.sfSymbolName }
}
