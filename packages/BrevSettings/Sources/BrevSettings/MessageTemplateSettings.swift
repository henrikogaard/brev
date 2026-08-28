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

/// A local reusable compose template.
///
/// Templates are always local; provider-native template APIs are a v2
/// concern and must be capability-gated before shipping. See ADR pending.
public struct MessageTemplate: Codable, Equatable, Sendable, Identifiable {
    /// Stable identifier.
    public let id: String
    /// Short human-readable name shown in the picker.
    public var name: String
    /// Plain-text body content.
    public var body: String
    /// Optional subject line; `nil` means "don't change the subject".
    public var subject: String?
    /// When set, restrict the template to a specific account.
    /// `nil` means the template is available for all accounts.
    public var accountID: String?
    /// Pinned templates appear at the top of the picker.
    public var isPinned: Bool
    /// ISO 8601 creation date. Used for stable sort order.
    public let createdAt: Date
    /// The last time this template was used.
    public var lastUsedAt: Date?

    public init(
        id: String = UUID().uuidString,
        name: String,
        body: String,
        subject: String? = nil,
        accountID: String? = nil,
        isPinned: Bool = false,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.body = body
        self.subject = subject
        self.accountID = accountID
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

public enum MessageTemplateMoveDirection: Sendable {
    case up
    case down
}

/// Persisted store for local message templates.
public struct MessageTemplateSettings: Codable, Equatable, Sendable {
    public enum Key {
        public static let templates = "messageTemplates.v1"
    }

    public var templates: [MessageTemplate]

    public static let defaults = MessageTemplateSettings(templates: [])

    public init(templates: [MessageTemplate]) {
        self.templates = templates
    }

    public static func load(from defaults: UserDefaults = .standard) -> MessageTemplateSettings {
        guard let data = defaults.data(forKey: Key.templates),
              let settings = try? JSONDecoder().decode(MessageTemplateSettings.self, from: data)
        else {
            return .defaults
        }
        return normalized(settings)
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Key.templates)
    }

    /// Templates visible for the given account, sorted pinned-first then in user order.
    ///
    /// Pass `nil` for `accountID` to see all global templates.
    public func templates(for accountID: String?) -> [MessageTemplate] {
        templates.enumerated()
            .filter { _, template in
                template.accountID == nil || template.accountID == accountID
            }
            .sorted { lhs, rhs in
                if lhs.element.isPinned != rhs.element.isPinned {
                    return lhs.element.isPinned
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    public mutating func add(_ template: MessageTemplate) {
        guard let normalizedTemplate = Self.normalized(template) else { return }
        if let index = duplicateIndex(for: normalizedTemplate, excludingID: nil) {
            var replacement = Self.replacing(
                templates[index],
                withContentFrom: normalizedTemplate
            )
            replacement.name = templates[index].name
            templates[index] = replacement
        } else {
            templates.append(normalizedTemplate)
        }
    }

    public mutating func update(_ template: MessageTemplate) {
        guard let normalizedTemplate = Self.normalized(template),
              let index = templates.firstIndex(where: { $0.id == normalizedTemplate.id }) else { return }
        if let duplicateIndex = duplicateIndex(
            for: normalizedTemplate,
            excludingID: normalizedTemplate.id
        ) {
            templates[duplicateIndex] = Self.replacing(
                templates[duplicateIndex],
                withContentFrom: normalizedTemplate
            )
            templates.remove(at: index)
        } else {
            templates[index] = Self.replacing(
                templates[index],
                withContentFrom: normalizedTemplate
            )
        }
    }

    public mutating func remove(id: MessageTemplate.ID) {
        templates.removeAll { $0.id == id }
    }

    /// Records usage — updates `lastUsedAt` for the given template.
    public mutating func recordUsage(id: MessageTemplate.ID, at date: Date = Date()) {
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return }
        templates[index].lastUsedAt = date
    }

    public mutating func togglePin(id: MessageTemplate.ID) {
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return }
        templates[index].isPinned.toggle()
    }

    public mutating func moveTemplate(
        id: MessageTemplate.ID,
        direction: MessageTemplateMoveDirection
    ) {
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return }
        let targetIndex: Int
        switch direction {
        case .up:
            guard index > templates.startIndex else { return }
            targetIndex = templates.index(before: index)
        case .down:
            guard index < templates.index(before: templates.endIndex) else { return }
            targetIndex = templates.index(after: index)
        }
        templates.swapAt(index, targetIndex)
    }

    public func canMoveTemplate(
        id: MessageTemplate.ID,
        direction: MessageTemplateMoveDirection
    ) -> Bool {
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return false }
        switch direction {
        case .up:
            return index > templates.startIndex
        case .down:
            return index < templates.index(before: templates.endIndex)
        }
    }

    private func duplicateIndex(
        for template: MessageTemplate,
        excludingID excludedID: MessageTemplate.ID?
    ) -> Int? {
        let name = Self.normalizedName(template.name)
        return templates.firstIndex { existing in
            existing.id != excludedID
                && Self.normalizedName(existing.name) == name
                && existing.accountID == template.accountID
        }
    }

    private static func normalized(_ settings: MessageTemplateSettings) -> MessageTemplateSettings {
        var normalizedSettings = MessageTemplateSettings.defaults
        for template in settings.templates {
            normalizedSettings.add(template)
        }
        return normalizedSettings
    }

    private static func normalized(_ template: MessageTemplate) -> MessageTemplate? {
        let name = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = template.subject?.trimmingCharacters(in: .whitespacesAndNewlines)
        let subjectHasContent = subject?.isEmpty == false
        guard !name.isEmpty else { return nil }
        return MessageTemplate(
            id: template.id,
            name: name,
            body: template.body,
            subject: subjectHasContent ? subject : nil,
            accountID: normalizedAccountID(template.accountID),
            isPinned: template.isPinned,
            createdAt: template.createdAt,
            lastUsedAt: template.lastUsedAt
        )
    }

    private static func replacing(
        _ existing: MessageTemplate,
        withContentFrom template: MessageTemplate
    ) -> MessageTemplate {
        MessageTemplate(
            id: existing.id,
            name: template.name,
            body: template.body,
            subject: template.subject,
            accountID: template.accountID,
            isPinned: template.isPinned,
            createdAt: existing.createdAt,
            lastUsedAt: template.lastUsedAt ?? existing.lastUsedAt
        )
    }

    private static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedAccountID(_ accountID: String?) -> String? {
        guard let accountID = accountID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accountID.isEmpty else {
            return nil
        }
        return accountID
    }
}
