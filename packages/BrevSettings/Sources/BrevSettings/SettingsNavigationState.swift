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
import Observation

public enum SettingsSectionAvailabilityKind: String, Sendable, Equatable {
    case shipped
    case capabilityGated
    case featureFlagged
    case hiddenRoadmap
}

/// Which settings section is currently visible. Drives the macOS
/// sidebar / detail layout and iOS programmatic navigation.
///
/// Case order defines the sidebar display order within each
/// `SettingsSectionGroup`. See `group` and `SettingsSectionGroup.allCases`.
public enum SettingsSection: String, Sendable, Hashable, CaseIterable, Identifiable {
    // Group: top (no header)
    case accounts
    // Group: app
    case appearance
    case notifications
    // Group: reading & composing
    case mailboxView
    case compose
    case signature
    /// Message templates, snippets, and canned replies.
    case templates
    /// Assisted drafting. Grouped with the other composition panes rather
    /// than with Privacy: it is a writing feature, and burying it under
    /// Privacy & Security made it read as a consent screen.
    case aiWriter
    /// VIP senders and follow-up reminders.
    case vipAndReminders
    /// Server-side and local mail rules.
    case rules
    /// Vacation auto-reply.
    case autoReply
    /// Mail-first calendar/contact scope, including current invite and
    /// autocomplete surfaces plus future read-only browsing. Lives with Mail
    /// because invites arrive as mail; it never had enough controls to earn
    /// its own sidebar group.
    case calendarContacts
    // Group: sync & storage
    /// Per-folder retention and auto-sync overrides.
    case folderSync
    /// Local mail cache, durable search index, and full-mail download controls.
    case mailStorage
    /// Local mail import/export tools.
    case importExport
    // Group: privacy & security
    case privacy
    /// Message encryption, certificates, and key management.
    case security
    // Group: advanced (collapsed until needed)
    case developer
    case updates
    case about

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .accounts: return String(localized: "Accounts", bundle: .module)
        case .appearance: return String(localized: "Appearance", bundle: .module)
        case .mailboxView: return String(localized: "Mailbox View", bundle: .module)
        case .signature: return String(localized: "Signature", bundle: .module)
        case .compose: return String(localized: "Compose", bundle: .module)
        case .templates: return String(localized: "Templates", bundle: .module)
        case .vipAndReminders: return String(localized: "VIP & Reminders", bundle: .module)
        case .rules: return String(localized: "Rules", bundle: .module)
        case .autoReply: return String(localized: "Auto-Reply", bundle: .module)
        case .folderSync: return String(localized: "Folder Sync", bundle: .module)
        case .mailStorage: return String(localized: "Mail Storage", bundle: .module)
        case .calendarContacts: return String(localized: "Calendar & Contacts", bundle: .module)
        case .importExport: return String(localized: "Import / Export", bundle: .module)
        case .security: return String(localized: "Security", bundle: .module)
        case .privacy: return String(localized: "Privacy", bundle: .module)
        case .notifications: return String(localized: "Notifications", bundle: .module)
        case .updates: return String(localized: "Updates", bundle: .module)
        case .aiWriter: return String(localized: "AI Writer", bundle: .module)
        case .developer: return String(localized: "Developer", bundle: .module)
        case .about: return String(localized: "About", bundle: .module)
        }
    }

    public var symbolName: String {
        switch self {
        case .accounts: return "person.crop.circle"
        case .appearance: return "paintpalette"
        case .mailboxView: return "list.bullet.rectangle"
        case .signature: return "signature"
        case .compose: return "square.and.pencil"
        case .templates: return "doc.text"
        case .vipAndReminders: return "star"
        case .rules: return "line.3.horizontal.decrease.circle"
        case .autoReply: return "airplane.departure"
        case .folderSync: return "folder.badge.gearshape"
        case .mailStorage: return "internaldrive"
        case .calendarContacts: return "calendar"
        case .importExport: return "square.and.arrow.up.on.square"
        case .security: return "lock.shield"
        case .privacy: return "hand.raised"
        case .notifications: return "bell"
        case .updates: return "arrow.triangle.2.circlepath"
        case .aiWriter: return "wand.and.stars"
        case .developer: return "hammer"
        case .about: return "info.circle"
        }
    }

    public var availability: SettingsSectionAvailabilityKind {
        switch self {
        case .updates, .developer:
            return .capabilityGated
        case .security:
            return .shipped
        case .accounts, .appearance, .mailboxView, .signature, .compose,
             .templates, .vipAndReminders, .rules, .autoReply,
             .folderSync, .mailStorage, .calendarContacts, .importExport, .privacy,
             .notifications, .aiWriter, .about:
            return .shipped
        }
    }

    public var isRoadmapOnly: Bool {
        availability == .hiddenRoadmap
    }

    /// Sidebar group this section belongs to. Groups are rendered with a
    /// header label above their rows; `.top` is ungrouped so Accounts sits at
    /// the very top while low-frequency destinations live
    /// in a collapsed Advanced group.
    public var group: SettingsSectionGroup {
        switch self {
        case .accounts: return .top
        case .appearance: return .app
        case .notifications, .mailboxView, .compose, .signature, .templates, .aiWriter:
            return .readingComposing
        case .vipAndReminders, .rules, .autoReply, .calendarContacts:
            return .organization
        case .folderSync, .mailStorage, .importExport: return .syncStorage
        case .privacy, .security: return .privacySecurity
        case .developer, .updates, .about: return .advanced
        }
    }

    /// Plain-language terms that make Settings search useful without requiring
    /// users to remember Brev's exact section titles.
    public var searchKeywords: [String] {
        switch self {
        case .accounts: return ["email", "mail account", "provider", "gmail", "google workspace", "imap"]
        case .appearance: return ["theme", "dark mode", "light mode", "color", "icon"]
        case .notifications: return ["alerts", "badges", "sounds"]
        case .mailboxView: return ["inbox", "message list", "reading pane", "density", "sidebar"]
        case .compose: return ["new message", "sending", "editor", "formatting"]
        case .signature: return ["sign-off", "footer"]
        case .templates: return ["snippets", "canned replies"]
        case .aiWriter: return ["writing", "assistant", "provider"]
        case .vipAndReminders: return ["important senders", "follow up", "reminders"]
        case .rules: return ["filters", "automation", "sieve"]
        case .autoReply: return ["vacation", "out of office"]
        case .calendarContacts: return ["invites", "address book", "autocomplete"]
        case .folderSync: return ["folders", "download", "offline", "retention"]
        case .mailStorage: return ["cache", "disk", "index", "download", "reset"]
        case .importExport: return ["backup", "archive", "move mail"]
        case .privacy: return ["remote images", "tracking", "avatars"]
        case .security: return ["encryption", "certificates", "keys", "smime"]
        case .developer: return ["debug", "diagnostics"]
        case .updates: return ["version", "download"]
        case .about: return ["license", "credits", "version"]
        }
    }

    /// Returns whether the section title, group, or plain-language keywords match a Settings query.
    public func matches(searchQuery query: String) -> Bool {
        let normalizedQuery = Self.normalizedSearchText(query)
        guard !normalizedQuery.isEmpty else { return true }
        let terms = [title, group.headerLabel ?? ""] + searchKeywords
        return terms.contains { Self.normalizedSearchText($0).contains(normalizedQuery) }
    }

    private static func normalizedSearchText(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Task-oriented sidebar grouping for settings sections. `.top` renders
/// without a header; the named groups render a header above their rows.
public enum SettingsSectionGroup: String, Sendable, Hashable, CaseIterable, Identifiable {
    case top
    case app
    case readingComposing
    case organization
    case syncStorage
    case privacySecurity
    case advanced

    public var id: String { rawValue }

    /// Header label shown above the group's rows in the sidebar.
    /// Returns `nil` for `.top` so Accounts renders ungrouped.
    public var headerLabel: String? {
        switch self {
        case .top: return nil
        case .app: return String(localized: "App", bundle: .module)
        case .readingComposing: return String(localized: "Reading & Composing", bundle: .module)
        case .organization: return String(localized: "Organization", bundle: .module)
        case .syncStorage: return String(localized: "Sync & Storage", bundle: .module)
        case .privacySecurity: return String(localized: "Privacy & Security", bundle: .module)
        case .advanced: return String(localized: "Advanced", bundle: .module)
        }
    }

    /// Display order. Matches `CaseIterable` order, but explicit so future
    /// reordering is self-documenting.
    public var sortOrder: Int {
        SettingsSectionGroup.allCases.firstIndex(of: self) ?? 0
    }
}

public struct SettingsSectionAvailability: Sendable, Equatable {
    public static let v1Default = SettingsSectionAvailability(
        visibleSections: SettingsSection.allCases.filter { $0.availability == .shipped }
    )

    public static let macOSDirectDownload = SettingsSectionAvailability(
        visibleSections: SettingsSection.allCases.filter {
            $0.availability == .shipped || $0 == .updates
        }
    )

    public static let macOSDeveloperDirectDownload = SettingsSectionAvailability(
        visibleSections: SettingsSectionAvailability.macOSDirectDownload.visibleSections + [.developer]
    )

    public static let allVisible = SettingsSectionAvailability(visibleSections: SettingsSection.allCases)

    public let visibleSections: [SettingsSection]

    public init(visibleSections: [SettingsSection]) {
        var seen = Set<SettingsSection>()
        let uniqueSections = visibleSections.filter { section in
            seen.insert(section).inserted
        }
        self.visibleSections = uniqueSections.isEmpty ? [.accounts] : uniqueSections
    }

    public func contains(_ section: SettingsSection) -> Bool {
        visibleSections.contains(section)
    }

    public func fallback(for section: SettingsSection) -> SettingsSection {
        contains(section) ? section : visibleSections[0]
    }

    /// Visible sections grouped by `SettingsSectionGroup`, in group-then-case
    /// order. Drives the grouped sidebar layout. Empty groups are omitted.
    public var groupedVisibleSections: [(group: SettingsSectionGroup, sections: [SettingsSection])] {
        groupedVisibleSections(matching: "")
    }

    /// Returns visible sections grouped in navigation order after applying a Settings query.
    public func groupedVisibleSections(
        matching query: String
    ) -> [(group: SettingsSectionGroup, sections: [SettingsSection])] {
        let visible = Set(visibleSections)
        return SettingsSectionGroup.allCases.compactMap { group in
            let sections = SettingsSection.allCases.filter {
                $0.group == group
                    && visible.contains($0)
                    && $0.matches(searchQuery: query)
            }
            return sections.isEmpty ? nil : (group, sections)
        }
    }
}

@MainActor
@Observable
public final class SettingsNavigationState {
    public private(set) var availability: SettingsSectionAvailability
    public private(set) var selected: SettingsSection

    public var visibleSections: [SettingsSection] {
        availability.visibleSections
    }

    public init(
        selected: SettingsSection = .accounts,
        availability: SettingsSectionAvailability = .v1Default
    ) {
        self.availability = availability
        self.selected = availability.fallback(for: selected)
    }

    public func select(_ section: SettingsSection) {
        selected = availability.fallback(for: section)
    }

    public func updateAvailability(_ availability: SettingsSectionAvailability) {
        self.availability = availability
        selected = availability.fallback(for: selected)
    }
}
