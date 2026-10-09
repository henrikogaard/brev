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

/// Keeps settings search honest on iPhone: rows that only exist on Mac are
/// not offered, and the badge row is found under its iPhone name.
enum SettingsSearchPlatformAdjustment {
    /// Titles with no iPhone counterpart: the sandbox cache path, the
    /// capability roadmap and the Mac-only import tools.
    private static var macOnlyTitles: Set<String> {
        [
            String(localized: "Cache location", bundle: .module),
            String(localized: "Capabilities and roadmap", bundle: .module),
            String(localized: "Available now", bundle: .module),
            String(localized: "Import mail", bundle: .module)
        ]
    }

    /// Applies the iPhone adjustments to a section's searchable titles.
    static func iOSTitles(from titles: [String]) -> [String] {
        let dockBadge = String(localized: "Show dock badge", bundle: .module)
        let hidden = macOnlyTitles
        return titles.compactMap { title in
            if title == dockBadge { return String(localized: "App icon badge", bundle: .module) }
            return hidden.contains(title) ? nil : title
        }
    }
}

struct SettingsSearchResult: Identifiable {
    let section: SettingsSection
    let title: String
    let target: String?
    var id: String { section.rawValue + ":" + title }
}

extension SettingsSection {
    var searchableControlTitles: [String] {
        #if os(macOS)
        switch self {
        case .appearance:
            return baseSearchableControlTitles + [
                String(localized: "Text and spacing", bundle: .module),
                String(localized: "Text size", bundle: .module),
                String(localized: "Interface density", bundle: .module)
            ]
        case .mailboxView:
            return baseSearchableControlTitles.filter {
                $0 != String(localized: "Text size", bundle: .module)
                    && $0 != String(localized: "List density", bundle: .module)
            }
        default: return baseSearchableControlTitles
        }
        #else
        return SettingsSearchPlatformAdjustment.iOSTitles(from: baseSearchableControlTitles)
        #endif
    }

    private var baseSearchableControlTitles: [String] {
        switch self {
        case .accounts: return [
                String(localized: "Remove", bundle: .module),
                String(localized: "Accounts", bundle: .module),
                String(localized: "Signed-in accounts", bundle: .module),
                String(localized: "Fetch schedule", bundle: .module),
                String(localized: "Check for mail", bundle: .module),
            ]
        case .appearance: return [
                String(localized: "Appearance", bundle: .module),
                String(localized: "Window transparency", bundle: .module),
                String(localized: "Background effect", bundle: .module),
                String(localized: "Transparency", bundle: .module),
                String(localized: "Unified title bar", bundle: .module),
                String(localized: "App icon", bundle: .module),
                String(localized: "Color and themes", bundle: .module),
                String(localized: "Mode", bundle: .module),
                String(localized: "Accent color", bundle: .module),
                String(localized: "Accent source", bundle: .module),
                String(localized: "Themes", bundle: .module),
                String(localized: "Window background opacity", bundle: .module),
                String(localized: "Sidebar background opacity", bundle: .module),
                String(localized: "Fonts", bundle: .module),
                // Former Mailbox View row name, kept so old searches still land on fonts.
                String(localized: "Message font", bundle: .module),
                String(localized: "Use One Font Everywhere", bundle: .module),
            ]
        case .mailboxView: return [
                String(localized: "Browser", bundle: .module),
                String(localized: "Open links in", bundle: .module),
                String(localized: "Mailbox View", bundle: .module),
                String(localized: "Folders", bundle: .module),
                String(localized: "Starred", bundle: .module),
                String(localized: "Snoozed", bundle: .module),
                String(localized: "Scheduled", bundle: .module),
                String(localized: "All mail", bundle: .module),
                String(localized: "Spam", bundle: .module),
                String(localized: "Trash", bundle: .module),
                String(localized: "Archive", bundle: .module),
                String(localized: "Reading", bundle: .module),
                String(localized: "Use rich HTML renderer", bundle: .module),
                String(localized: "Conversation order", bundle: .module),
                String(localized: "Text size", bundle: .module),
                String(localized: "Mailbox list", bundle: .module),
                String(localized: "Group conversations", bundle: .module),
                String(localized: "Group by received date", bundle: .module),
                String(localized: "Show arrival time", bundle: .module),
                String(localized: "Show sender images", bundle: .module),
                String(localized: "Sort order", bundle: .module),
                String(localized: "Preview lines", bundle: .module),
                String(localized: "List density", bundle: .module),
                String(localized: "Reading pane", bundle: .module),
                String(localized: "Show folder stats", bundle: .module),
                String(localized: "Inbox classification", bundle: .module),
                String(localized: "Stats detail", bundle: .module),
            ]
        case .compose: return [
                String(localized: "Compose", bundle: .module),
                String(localized: "Defaults", bundle: .module),
                String(localized: "Message format", bundle: .module),
                String(localized: "Quoted text", bundle: .module),
                String(localized: "Check spelling while typing", bundle: .module),
                String(localized: "Send safety", bundle: .module),
                String(localized: "Attachment reminder", bundle: .module),
                String(localized: "External recipient warning", bundle: .module),
                String(localized: "Undo send delay", bundle: .module),
                String(localized: "Recipient suggestions", bundle: .module),
                String(localized: "Use Contacts app", bundle: .module),
            ]
        case .signature: return [
                String(localized: "Signature", bundle: .module),
                String(localized: "Signature library", bundle: .module),
                String(localized: "Default per account", bundle: .module),
            ]
        case .templates: return [
                String(localized: "Templates", bundle: .module),
                String(localized: "Saved templates", bundle: .module),
                String(localized: "Name", bundle: .module),
                String(localized: "Scope", bundle: .module),
                String(localized: "Subject (optional)", bundle: .module),
                String(localized: "Body", bundle: .module),
            ]
        case .vipAndReminders: return [
                String(localized: "VIP & Reminders", bundle: .module),
                String(localized: "VIP senders", bundle: .module),
                String(localized: "Blocked senders", bundle: .module),
                String(localized: "Follow-up reminders", bundle: .module),
            ]
        case .smartViews: return [
                String(localized: "Show Smart Views in sidebar", bundle: .module),
                String(localized: "Display order", bundle: .module),
                String(localized: "New Smart View", bundle: .module),
            ]
        case .rules: return [
                String(localized: "Rules", bundle: .module),
                String(localized: "Server rules", bundle: .module),
                String(localized: "Configured rules", bundle: .module),
                String(localized: "Local rules", bundle: .module),
                String(localized: "Run local rules automatically", bundle: .module),
            ]
        case .autoReply: return [
                String(localized: "Auto-Reply", bundle: .module),
                String(localized: "Vacation responder", bundle: .module),
                String(localized: "Send automatic reply", bundle: .module),
                String(localized: "Repeats on weekdays", bundle: .module),
            ]
        case .folderSync: return [
                String(localized: "Folder Sync", bundle: .module),
                String(localized: "Per-folder overrides", bundle: .module),
                String(localized: "Show in mailbox list", bundle: .module),
                String(localized: "Retention", bundle: .module),
                String(localized: "Related mail", bundle: .module),
                String(localized: "Automatically load related mail", bundle: .module),
            ]
        case .mailStorage: return [
                String(localized: "Reset & re-download local mail?", bundle: .module),
                String(localized: "Mail cache", bundle: .module),
                String(localized: "Draft staging", bundle: .module),
                String(localized: "Offline sync metadata", bundle: .module),
                String(localized: "Search index database", bundle: .module),
                String(localized: "Mail Storage", bundle: .module),
                String(localized: "Local data", bundle: .module),
                String(localized: "Size on disk", bundle: .module),
                String(localized: "Cache location", bundle: .module),
                String(localized: "Breakdown", bundle: .module),
                String(localized: "Details", bundle: .module),
                String(localized: "Search index", bundle: .module),
                String(localized: "Search", bundle: .module),
                String(localized: "Local search", bundle: .module),
                String(localized: "Local retention", bundle: .module),
                String(localized: "Cache lookback", bundle: .module),
                String(localized: "Download", bundle: .module),
                String(localized: "Reset", bundle: .module),
            ]
        case .calendarContacts: return [
                String(localized: "Calendar & Contacts", bundle: .module),
                String(localized: "Sources", bundle: .module),
                String(localized: "Add DAV Source…", bundle: .module),
                String(localized: "Enable Calendar", bundle: .module),
                String(localized: "Enable Contacts", bundle: .module),
                String(localized: "Enable Tasks", bundle: .module),
                String(localized: "Google Calendar & Contacts", bundle: .module),
                String(localized: "Calendar invites", bundle: .module),
                String(localized: "Accepted invite write target", bundle: .module),
                String(localized: "Compose contact suggestions", bundle: .module),
                String(localized: "DAV source connections", bundle: .module),
                String(localized: "Calendar browsing", bundle: .module),
                String(localized: "Contacts browsing", bundle: .module),
                String(localized: "Tasks browsing", bundle: .module),
                String(localized: "Event editing", bundle: .module),
                String(localized: "Contact editing", bundle: .module),
                String(localized: "Task editing", bundle: .module),
                String(localized: "Calendar/contact search results", bundle: .module),
                String(localized: "Capabilities and roadmap", bundle: .module),
                String(localized: "Available now", bundle: .module),
                String(localized: "Not available yet", bundle: .module),
            ]
        case .importExport: return [
                String(localized: "Import / Export", bundle: .module),
                String(localized: "Import mail", bundle: .module),
                String(localized: "Export mail", bundle: .module),
            ]
        case .security: return [
                String(localized: "Security", bundle: .module),
                String(localized: "Message security", bundle: .module),
                String(localized: "Compose defaults", bundle: .module),
                String(localized: "Enable S/MIME", bundle: .module),
                String(localized: "Prefer signing", bundle: .module),
                String(localized: "Prefer encryption", bundle: .module),
                String(localized: "Local key material", bundle: .module),
                String(localized: "Import and export preferences", bundle: .module),
                String(localized: "S/MIME export format", bundle: .module),
                String(localized: "Allow private material in exports", bundle: .module),
                String(localized: "Replace existing records on import", bundle: .module),
            ]
        case .preferenceSync: return [
                String(localized: "iCloud sync", bundle: .module),
                String(localized: "Sync preferences with iCloud", bundle: .module),
            ]
        case .privacy: return [
                String(localized: "Always load remote images", bundle: .module),
                String(localized: "Sender image sources", bundle: .module),
                String(localized: "Use Contacts photos", bundle: .module),
                String(localized: "Use Gravatar", bundle: .module),
                String(localized: "Use BIMI logos", bundle: .module),
                String(localized: "Use domain favicons", bundle: .module),

                String(localized: "Privacy", bundle: .module),
                String(localized: "Defaults", bundle: .module),
                String(localized: "Remote content starts blocked", bundle: .module),
                String(localized: "Sender icons are explicit", bundle: .module),
                String(localized: "AI Writer requires consent", bundle: .module),
                String(localized: "Remote content allowlist", bundle: .module),
            ]
        case .notifications: return [
                String(localized: "Notifications", bundle: .module),
                String(localized: "Enable notifications", bundle: .module),
                String(localized: "Show dock badge", bundle: .module),
                String(localized: "App badge", bundle: .module),
                String(localized: "Notification sound", bundle: .module),
                String(localized: "Show message previews", bundle: .module),
                String(localized: "Accounts", bundle: .module),
                String(localized: "Badge", bundle: .module),
                String(localized: "Sound", bundle: .module),
                String(localized: "Quiet hours", bundle: .module),
                String(localized: "Enable quiet hours", bundle: .module),
                String(localized: "Starts at", bundle: .module),
                String(localized: "Ends at", bundle: .module),
            ]
        case .updates: return [
                String(localized: "Updates", bundle: .module),
                String(localized: "Check cadence", bundle: .module),
                String(localized: "Update checks", bundle: .module),
                String(localized: "Release channel", bundle: .module),
                String(localized: "Channel", bundle: .module),
                String(localized: "GitHub releases", bundle: .module),
                String(localized: "Sparkle", bundle: .module),
            ]
        case .aiWriter: return [
                String(localized: "AI Writer", bundle: .module),
                String(localized: "Availability", bundle: .module),
                String(localized: "Enable AI Writer", bundle: .module),
            ]
        case .developer: return [
                String(localized: "Developer", bundle: .module),
                String(localized: "Runtime", bundle: .module),
                String(localized: "Demo mailbox mode", bundle: .module),
            ]
        case .about: return [
                String(localized: "About", bundle: .module),
            ]
        }
    }
}

extension SettingsSearchResult {
    static func results(for query: String, sections: [SettingsSection]) -> [Self] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return sections.flatMap { section in
            let controls = section.searchableControlTitles.filter {
                $0.localizedStandardContains(query)
            }
            if !controls.isEmpty {
                return controls.map { Self(section: section, title: $0, target: $0) }
            }
            return section.matches(searchQuery: query)
                ? [Self(section: section, title: section.title, target: nil)] : []
        }
    }
}

private struct SettingsSearchTargetKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

private struct SettingsScopeCaptionKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

private struct SettingsScopeAccessoryKey: EnvironmentKey {
    static let defaultValue: AnyView? = nil
}

extension EnvironmentValues {
    var settingsSearchTarget: String? {
        get { self[SettingsSearchTargetKey.self] }
        set { self[SettingsSearchTargetKey.self] = newValue }
    }

    /// Optional scope note (e.g. "Applies to all mailboxes") rendered by
    /// SectionScaffold directly beneath the pane subtitle.
    var settingsScopeCaption: String? {
        get { self[SettingsScopeCaptionKey.self] }
        set { self[SettingsScopeCaptionKey.self] = newValue }
    }

    /// Optional scope control (e.g. the mailbox picker) that SectionScaffold
    /// scrolls with the pane instead of pinning above it.
    var settingsScopeAccessory: AnyView? {
        get { self[SettingsScopeAccessoryKey.self] }
        set { self[SettingsScopeAccessoryKey.self] = newValue }
    }
}
