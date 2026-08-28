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

enum ComposeMessageFormat: String, CaseIterable, Sendable {
    case automatic
    case richText
    case plainText

    var title: String {
        switch self {
        case .automatic: return String(localized: "Automatic", bundle: .module)
        case .richText: return "Rich Text"
        case .plainText: return "Plain Text"
        }
    }
}

enum ComposeQuotePlacement: String, CaseIterable, Sendable {
    case belowReply
    case aboveReply

    var title: String {
        switch self {
        case .belowReply: return String(localized: "Below reply", bundle: .module)
        case .aboveReply: return String(localized: "Above reply", bundle: .module)
        }
    }
}

enum ComposeUndoSendDelay: Int, CaseIterable, Sendable {
    case off = 0
    case fiveSeconds = 5
    case tenSeconds = 10
    case thirtySeconds = 30

    var title: String {
        switch self {
        case .off: return String(localized: "Off", bundle: .module)
        case .fiveSeconds: return String(localized: "5 seconds", bundle: .module)
        case .tenSeconds: return String(localized: "10 seconds", bundle: .module)
        case .thirtySeconds: return String(localized: "30 seconds", bundle: .module)
        }
    }
}

struct ComposeSettings: Equatable, Sendable {
    enum Key {
        static let messageFormat = "compose.messageFormat"
        static let attachmentReminderEnabled = "compose.attachmentReminderEnabled"
        static let externalRecipientWarningEnabled = "compose.externalRecipientWarningEnabled"
        static let quotePlacement = "compose.quotePlacement"
        static let undoSendDelay = "compose.undoSendDelay"
        static let textCheckingEnabled = "compose.textChecking.enabled"
    }

    var messageFormat: ComposeMessageFormat
    var attachmentReminderEnabled: Bool
    var externalRecipientWarningEnabled: Bool
    var quotePlacement: ComposeQuotePlacement
    var undoSendDelay: ComposeUndoSendDelay
    var textCheckingEnabled: Bool

    static let defaults = ComposeSettings(
        messageFormat: .automatic,
        attachmentReminderEnabled: true,
        externalRecipientWarningEnabled: true,
        quotePlacement: .belowReply,
        undoSendDelay: .off,
        textCheckingEnabled: true
    )

    static func load(from defaults: UserDefaults = .standard) -> ComposeSettings {
        ComposeSettings(
            messageFormat: enumValue(
                ComposeMessageFormat.self,
                for: Key.messageFormat,
                defaultValue: Self.defaults.messageFormat,
                defaults: defaults
            ),
            attachmentReminderEnabled: bool(
                for: Key.attachmentReminderEnabled,
                defaultValue: Self.defaults.attachmentReminderEnabled,
                defaults: defaults
            ),
            externalRecipientWarningEnabled: bool(
                for: Key.externalRecipientWarningEnabled,
                defaultValue: Self.defaults.externalRecipientWarningEnabled,
                defaults: defaults
            ),
            quotePlacement: enumValue(
                ComposeQuotePlacement.self,
                for: Key.quotePlacement,
                defaultValue: Self.defaults.quotePlacement,
                defaults: defaults
            ),
            undoSendDelay: intEnumValue(
                ComposeUndoSendDelay.self,
                for: Key.undoSendDelay,
                defaultValue: Self.defaults.undoSendDelay,
                defaults: defaults
            ),
            textCheckingEnabled: bool(
                for: Key.textCheckingEnabled,
                defaultValue: Self.defaults.textCheckingEnabled,
                defaults: defaults
            )
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(messageFormat.rawValue, forKey: Key.messageFormat)
        defaults.set(attachmentReminderEnabled, forKey: Key.attachmentReminderEnabled)
        defaults.set(externalRecipientWarningEnabled, forKey: Key.externalRecipientWarningEnabled)
        defaults.set(quotePlacement.rawValue, forKey: Key.quotePlacement)
        defaults.set(undoSendDelay.rawValue, forKey: Key.undoSendDelay)
        defaults.set(textCheckingEnabled, forKey: Key.textCheckingEnabled)
    }

    private static func bool(
        for key: String,
        defaultValue: Bool,
        defaults: UserDefaults
    ) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    private static func enumValue<Value>(
        _ type: Value.Type,
        for key: String,
        defaultValue: Value,
        defaults: UserDefaults
    ) -> Value where Value: RawRepresentable, Value.RawValue == String {
        guard let rawValue = defaults.string(forKey: key),
              let value = Value(rawValue: rawValue) else {
            return defaultValue
        }
        return value
    }

    private static func intEnumValue<Value>(
        _ type: Value.Type,
        for key: String,
        defaultValue: Value,
        defaults: UserDefaults
    ) -> Value where Value: RawRepresentable, Value.RawValue == Int {
        guard defaults.object(forKey: key) != nil,
              let value = Value(rawValue: defaults.integer(forKey: key)) else {
            return defaultValue
        }
        return value
    }
}
