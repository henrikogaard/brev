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

/// Task destinations group stable leaf IDs without migrating saved preferences or deep links.
enum SettingsCategory: String, CaseIterable, Identifiable {
    case accountsConnections, appearance, mailboxesReading, writing, notifications
    case rulesOrganization, privacySecurity, syncStorage, aboutUpdates, developer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accountsConnections: String(localized: "Accounts & Connections", bundle: .module)
        case .appearance: String(localized: "Appearance", bundle: .module)
        case .mailboxesReading: String(localized: "Mailboxes & Reading", bundle: .module)
        case .writing: String(localized: "Writing", bundle: .module)
        case .notifications: String(localized: "Notifications", bundle: .module)
        case .rulesOrganization: String(localized: "Rules & Organisation", bundle: .module)
        case .privacySecurity: String(localized: "Privacy & Security", bundle: .module)
        case .syncStorage: String(localized: "Sync & Storage", bundle: .module)
        case .aboutUpdates: String(localized: "About & Updates", bundle: .module)
        case .developer: String(localized: "Developer", bundle: .module)
        }
    }

    var symbolName: String {
        switch self {
        case .accountsConnections: "person.crop.circle"
        case .appearance: "paintpalette"
        case .mailboxesReading: "tray.2"
        case .writing: "square.and.pencil"
        case .notifications: "bell"
        case .rulesOrganization: "line.3.horizontal.decrease.circle"
        case .privacySecurity: "lock.shield"
        case .syncStorage: "internaldrive"
        case .aboutUpdates: "info.circle"
        case .developer: "hammer"
        }
    }

    var isSupplementary: Bool { self == .aboutUpdates || self == .developer }

    func sections(in availability: SettingsSectionAvailability) -> [SettingsSection] {
        let order: [SettingsSection] = switch self {
        case .accountsConnections: [.accounts, .calendarContacts]
        case .appearance: [.appearance]
        case .mailboxesReading: [.mailboxView, .smartViews]
        case .writing: [.compose, .signature, .templates, .aiWriter]
        case .notifications: [.notifications]
        case .rulesOrganization: [.rules, .vipAndReminders, .autoReply]
        case .privacySecurity: [.privacy, .security]
        case .syncStorage: [.folderSync, .mailStorage, .preferenceSync, .importExport]
        case .aboutUpdates: [.about, .updates]
        case .developer: [.developer]
        }
        return order.filter { availability.contains($0) }
    }
}

extension SettingsSection {
    var category: SettingsCategory {
        switch self {
        case .accounts, .calendarContacts: .accountsConnections
        case .appearance: .appearance
        case .mailboxView, .smartViews: .mailboxesReading
        case .compose, .signature, .templates, .aiWriter: .writing
        case .notifications: .notifications
        case .rules, .vipAndReminders, .autoReply: .rulesOrganization
        case .privacy, .security: .privacySecurity
        case .folderSync, .mailStorage, .preferenceSync, .importExport: .syncStorage
        case .about, .updates: .aboutUpdates
        case .developer: .developer
        }
    }
}

extension SettingsSectionAvailability {
    var visibleCategories: [SettingsCategory] {
        SettingsCategory.allCases.filter { !$0.sections(in: self).isEmpty }
    }
}
