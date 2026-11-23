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

/// Device-local preferences for macOS mail-pane keyboard input.
public enum MailKeyboardPreferences {
    /// Whether pressing a letter in the focused mailbox performs its mail action. Defaults to true.
    public static let singleKeyShortcuts = "mail.keyboard.singleKeyShortcuts"

    /// Reads the single-key preference, treating an unset value as on.
    public static func singleKeyShortcutsEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: singleKeyShortcuts) as? Bool ?? true
    }
}
