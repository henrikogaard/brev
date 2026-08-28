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

/// Decides which command groups a platform's menu/keyboard surface
/// includes. Print is cross-platform now that iOS gains print/PDF
/// export; import/export and the keyboard-shortcuts window remain
/// macOS-only (no iOS analogue).
public struct MailCommandPlatformPolicy: Equatable, Sendable {
    public enum Platform: Sendable { case macOS, iOS }

    public let includesMessageCommands: Bool
    public let includesComposeCommands: Bool
    public let includesPrintCommands: Bool
    public let includesImportExportCommands: Bool
    public let includesFolderMBOXExportCommand: Bool
    public let includesKeyboardShortcutsWindowCommand: Bool

    public static func forPlatform(_ platform: Platform) -> MailCommandPlatformPolicy {
        switch platform {
        case .macOS:
            return MailCommandPlatformPolicy(
                includesMessageCommands: true,
                includesComposeCommands: true,
                includesPrintCommands: true,
                includesImportExportCommands: true,
                includesFolderMBOXExportCommand: false,
                includesKeyboardShortcutsWindowCommand: true
            )
        case .iOS:
            return MailCommandPlatformPolicy(
                includesMessageCommands: true,
                includesComposeCommands: true,
                includesPrintCommands: true,
                includesImportExportCommands: false,
                includesFolderMBOXExportCommand: false,
                includesKeyboardShortcutsWindowCommand: false
            )
        }
    }

    public static var current: MailCommandPlatformPolicy {
        #if os(macOS)
        forPlatform(.macOS)
        #else
        forPlatform(.iOS)
        #endif
    }
}
