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
import BrevSettings
import Foundation
#if os(macOS)
import AppKit
#elseif os(iOS)
import UserNotifications
#endif

enum MailBadgePresentation {
    static func unreadCount(
        folders: [Folder],
        sourceSections: [MailSourceSection],
        settings: NotificationSettings
    ) -> Int {
        guard settings.badgeEnabled else { return 0 }

        switch settings.badgePolicy {
        case .off:
            return 0
        case .allUnread:
            if sourceSections.isEmpty {
                return folders.reduce(into: 0) { count, folder in
                    count += folder.unreadCount
                }
            }
            return sourceSections.reduce(into: 0) { count, section in
                count += section.folders.reduce(into: 0) { sectionCount, folder in
                    sectionCount += folder.unreadCount
                }
            }
        case .inboxUnread:
            if sourceSections.isEmpty {
                return folders.first { $0.role == .inbox }?.unreadCount ?? 0
            }
            return sourceSections.reduce(into: 0) { count, section in
                count += section.folders.first { $0.role == .inbox }?.unreadCount ?? 0
            }
        case .selectedSources:
            if sourceSections.isEmpty {
                return folders.first { $0.role == .inbox }?.unreadCount ?? 0
            }
            return sourceSections.reduce(into: 0) { count, section in
                guard settings.accountOverride(for: section.id.accountID).badgeEnabled else { return }
                count += section.folders.first { $0.role == .inbox }?.unreadCount ?? 0
            }
        }
    }

    #if os(macOS)
    @MainActor
    static func apply(unreadCount: Int) {
        NSApp.dockTile.badgeLabel = unreadCount > 0 ? "\(unreadCount)" : nil
    }

    #elseif os(iOS)
    @MainActor
    static func apply(unreadCount: Int) {
        // Same process guard as BrevLocalNotificationCenter — xctest / SPM
        // runners crash on UNUserNotificationCenter.current().
        guard BrevLocalNotificationCenter.canUseSystemNotificationCenterInCurrentProcess else {
            return
        }
        UNUserNotificationCenter.current().setBadgeCount(unreadCount)
    }
    #else
    @MainActor
    static func apply(unreadCount: Int) {
        _ = unreadCount
    }
    #endif
}
