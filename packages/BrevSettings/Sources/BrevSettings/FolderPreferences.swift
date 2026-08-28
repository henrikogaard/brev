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

struct FolderPreferences: Equatable, Sendable {
    enum Key {
        static let showStarred = "folders.showStarred"
        static let showSnoozed = "folders.showSnoozed"
        static let showScheduled = "folders.showScheduled"
        static let showAllMail = "folders.showAllMail"
        static let showSpam = "folders.showSpam"
        static let showTrash = "folders.showTrash"
        static let showArchive = "folders.showArchive"
    }

    var showStarred: Bool
    var showSnoozed: Bool
    var showScheduled: Bool
    var showAllMail: Bool
    var showSpam: Bool
    var showTrash: Bool
    var showArchive: Bool

    static let defaults = FolderPreferences(
        showStarred: true,
        showSnoozed: true,
        showScheduled: true,
        showAllMail: false,
        showSpam: true,
        showTrash: true,
        showArchive: true
    )

    static func load(from defaults: UserDefaults = .standard) -> FolderPreferences {
        FolderPreferences(
            showStarred: bool(for: Key.showStarred, default: Self.defaults.showStarred, defaults: defaults),
            showSnoozed: bool(for: Key.showSnoozed, default: Self.defaults.showSnoozed, defaults: defaults),
            showScheduled: bool(for: Key.showScheduled, default: Self.defaults.showScheduled, defaults: defaults),
            showAllMail: bool(for: Key.showAllMail, default: Self.defaults.showAllMail, defaults: defaults),
            showSpam: bool(for: Key.showSpam, default: Self.defaults.showSpam, defaults: defaults),
            showTrash: bool(for: Key.showTrash, default: Self.defaults.showTrash, defaults: defaults),
            showArchive: bool(for: Key.showArchive, default: Self.defaults.showArchive, defaults: defaults)
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(showStarred, forKey: Key.showStarred)
        defaults.set(showSnoozed, forKey: Key.showSnoozed)
        defaults.set(showScheduled, forKey: Key.showScheduled)
        defaults.set(showAllMail, forKey: Key.showAllMail)
        defaults.set(showSpam, forKey: Key.showSpam)
        defaults.set(showTrash, forKey: Key.showTrash)
        defaults.set(showArchive, forKey: Key.showArchive)
    }

    private static func bool(for key: String, default defaultValue: Bool, defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) != nil ? defaults.bool(forKey: key) : defaultValue
    }
}
