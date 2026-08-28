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

public enum MailWeekday: String, Sendable, Hashable, Codable, CaseIterable {
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday
}

public enum VacationResponderRecurrence: Sendable, Hashable, Codable {
    case none
    case weekly(days: Set<MailWeekday>)
}

public struct VacationResponderSchedule: Sendable, Hashable, Codable {
    public let startsAt: Date?
    public let endsAt: Date?
    public let recurrence: VacationResponderRecurrence

    public init(
        startsAt: Date? = nil,
        endsAt: Date? = nil,
        recurrence: VacationResponderRecurrence = .none
    ) {
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.recurrence = recurrence
    }
}

public struct VacationResponderSettings: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public let name: String
    public let isEnabled: Bool
    public let message: String
    public let schedule: VacationResponderSchedule
    public let excludedRecipients: [String]
    public let replyFrom: Correspondent?

    public init(
        id: String,
        name: String,
        isEnabled: Bool,
        message: String,
        schedule: VacationResponderSchedule = VacationResponderSchedule(),
        excludedRecipients: [String] = [],
        replyFrom: Correspondent? = nil
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.message = message
        self.schedule = schedule
        self.excludedRecipients = excludedRecipients
        self.replyFrom = replyFrom
    }
}

public struct VacationResponderDraft: Sendable, Hashable, Codable {
    public let id: String?
    public let name: String
    public let isEnabled: Bool
    public let message: String
    public let startsAt: Date?
    public let endsAt: Date?
    public let recurrence: VacationResponderRecurrence
    public let excludedRecipients: [String]
    public let replyFrom: Correspondent?

    public init(
        id: String? = nil,
        name: String,
        isEnabled: Bool,
        message: String,
        startsAt: Date? = nil,
        endsAt: Date? = nil,
        recurrence: VacationResponderRecurrence = .none,
        excludedRecipients: [String] = [],
        replyFrom: Correspondent? = nil
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.message = message
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.recurrence = recurrence
        self.excludedRecipients = excludedRecipients
        self.replyFrom = replyFrom
    }

    public var validationErrors: Set<VacationResponderValidationError> {
        var errors: Set<VacationResponderValidationError> = []
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.insert(.emptyMessage)
        }
        if let startsAt, let endsAt, endsAt < startsAt {
            errors.insert(.endsBeforeStart)
        }
        for recipient in excludedRecipients where !recipient.isPlausibleEmailAddress {
            errors.insert(.invalidExcludedRecipient(recipient))
        }
        return errors
    }
}

public enum VacationResponderValidationError: Sendable, Hashable, Codable {
    case emptyMessage
    case endsBeforeStart
    case invalidExcludedRecipient(String)
}

private extension String {
    var isPlausibleEmailAddress: Bool {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        guard let at = value.firstIndex(of: "@"), at != value.startIndex else {
            return false
        }
        let domainStart = value.index(after: at)
        guard domainStart < value.endIndex else { return false }
        let domain = value[domainStart...]
        return domain.contains(".") && !value.contains(where: \.isWhitespace)
    }
}
