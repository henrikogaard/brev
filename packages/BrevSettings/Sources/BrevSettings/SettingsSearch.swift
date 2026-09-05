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

struct SettingsSearchResult: Identifiable {
    let section: SettingsSection
    let title: String
    let target: String?
    var id: String { section.rawValue + ":" + title }
}

extension SettingsSection {
    var searchableControlTitles: [String] {
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
                String(localized: "Window design", bundle: .module),
                String(localized: "Style", bundle: .module),
                String(localized: "Apply to", bundle: .module),
                String(localized: "Unified title bar", bundle: .module),
                String(localized: "App icon", bundle: .module),
                String(localized: "Color and themes", bundle: .module),
                String(localized: "Mode", bundle: .module),
                String(localized: "Pane opacity", bundle: .module),
                String(localized: "Sidebar opacity", bundle: .module),
                String(localized: "Message content", bundle: .module),
                String(localized: "Message opacity", bundle: .module),
            ]
        case .mailboxView: return [
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
                String(localized: "Always load remote images", bundle: .module),
                String(localized: "Conversation order", bundle: .module),
                String(localized: "Message font", bundle: .module),
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
                String(localized: "Search", bundle: .module),
                String(localized: "Sender image sources", bundle: .module),
                String(localized: "Use Contacts photos", bundle: .module),
                String(localized: "Use Gravatar", bundle: .module),
                String(localized: "Use BIMI logos", bundle: .module),
                String(localized: "Use domain favicons", bundle: .module),
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
                String(localized: "Show in mailbox list", bundle: .module),
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
                String(localized: "Local retention", bundle: .module),
                String(localized: "Cache lookback", bundle: .module),
                String(localized: "Download", bundle: .module),
                String(localized: "Reset", bundle: .module),
            ]
        case .calendarContacts: return [
                String(localized: "Calendar invites", bundle: .module),
                String(localized: "Accepted invite write target", bundle: .module),
                String(localized: "Compose contact suggestions", bundle: .module),
                String(localized: "Read-only calendar browsing", bundle: .module),
                String(localized: "Read-only contacts browsing", bundle: .module),
                String(localized: "Calendar/contact search results", bundle: .module),
                String(localized: "Full calendar editing", bundle: .module),
                String(localized: "Full contacts management", bundle: .module),
                String(localized: "Calendar & Contacts", bundle: .module),
                String(localized: "Available now", bundle: .module),
                String(localized: "Planned after DAV verification", bundle: .module),
                String(localized: "Out of scope", bundle: .module),
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
        case .privacy: return [
                String(localized: "Privacy", bundle: .module),
                String(localized: "Defaults", bundle: .module),
                String(localized: "Remote content starts blocked", bundle: .module),
                String(localized: "Sender icons are explicit", bundle: .module),
                String(localized: "AI Writer requires consent", bundle: .module),
                String(localized: "Browser", bundle: .module),
                String(localized: "Open links in", bundle: .module),
                String(localized: "Remote content allowlist", bundle: .module),
                String(localized: "Current opt-ins", bundle: .module),
                String(localized: "iCloud sync", bundle: .module),
                String(localized: "Sync preferences with iCloud", bundle: .module),
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

extension EnvironmentValues {
    var settingsSearchTarget: String? {
        get { self[SettingsSearchTargetKey.self] }
        set { self[SettingsSearchTargetKey.self] = newValue }
    }
}
