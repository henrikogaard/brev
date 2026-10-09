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

/// A part of the mail window that has its own font family (ADR-0086).
/// Compose follows `reader`; settings and window chrome stay System.
public enum BrevFontSection: String, Sendable, Hashable, CaseIterable, Identifiable {
    case sidebar
    case messageList
    case reader

    public var id: String { rawValue }

    /// `UserDefaults` key holding this section's `MailboxFontFamily` raw value.
    public var preferenceKey: String {
        "font.\(rawValue)"
    }

    public var title: String {
        switch self {
        case .sidebar: return String(localized: "Sidebar", bundle: .module)
        case .messageList: return String(localized: "Message list", bundle: .module)
        case .reader: return String(localized: "Reading and compose", bundle: .module)
        }
    }

    public var symbolName: String {
        switch self {
        case .sidebar: return "sidebar.left"
        case .messageList: return "list.bullet.rectangle"
        case .reader: return "text.alignleft"
        }
    }

    /// Resolves the family from raw stored values. An unset or unknown section
    /// value falls back to the legacy message font for mail content, so
    /// upgrades look the same; the sidebar never followed it and uses System.
    public func resolve(sectionRaw: String?, legacyRaw: String?) -> MailboxFontFamily {
        if let sectionRaw, let family = MailboxFontFamily(rawValue: sectionRaw) {
            return family
        }
        guard self != .sidebar, let legacyRaw else { return .system }
        return MailboxFontFamily(rawValue: legacyRaw) ?? .system
    }

    /// Resolves the family stored in `defaults`.
    public func resolvedFamily(in defaults: UserDefaults) -> MailboxFontFamily {
        resolve(
            sectionRaw: defaults.string(forKey: preferenceKey),
            legacyRaw: defaults.string(forKey: MailboxViewPreferenceKey.fontFamily)
        )
    }
}

/// Live font family for one section, updating when its preference changes.
@propertyWrapper
public struct SectionFontFamily: DynamicProperty {
    @AppStorage private var sectionRaw: String
    @AppStorage private var legacyRaw: String
    private let section: BrevFontSection

    public init(_ section: BrevFontSection, store: UserDefaults? = nil) {
        self.section = section
        _sectionRaw = AppStorage(wrappedValue: "", section.preferenceKey, store: store)
        _legacyRaw = AppStorage(
            wrappedValue: MailboxFontFamily.system.rawValue,
            MailboxViewPreferenceKey.fontFamily,
            store: store
        )
    }

    public var wrappedValue: MailboxFontFamily {
        section.resolve(sectionRaw: sectionRaw, legacyRaw: legacyRaw)
    }
}

public extension EnvironmentValues {
    /// Font family `brevFont` tokens use; set per pane by `brevFontSection(_:)`.
    @Entry var brevFontFamily: MailboxFontFamily = .system
}

public extension View {
    /// Applies a section's saved font family to `brevFont` tokens below this
    /// view. Attach toolbars outside it so window chrome stays System.
    func brevFontSection(_ section: BrevFontSection) -> some View {
        modifier(BrevFontSectionModifier(family: SectionFontFamily(section)))
    }
}

private struct BrevFontSectionModifier: ViewModifier {
    let family: SectionFontFamily

    func body(content: Content) -> some View {
        content.environment(\.brevFontFamily, family.wrappedValue)
    }
}
