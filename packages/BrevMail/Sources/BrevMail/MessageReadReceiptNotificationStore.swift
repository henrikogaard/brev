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
import Foundation

struct MessageReadReceiptNotificationRecord: Sendable, Hashable, Codable {
    let originalMessageID: String
    let finalRecipient: String?
    let disposition: String
    let receiptMessageID: MessageHeader.ID
    let receivedAt: Date
}

struct MessageReadReceiptNotificationStore {
    static let shared = MessageReadReceiptNotificationStore()

    private let defaults: UserDefaults
    private let maxRecords: Int

    init(defaults: UserDefaults = .standard, maxRecords: Int = 200) {
        self.defaults = defaults
        self.maxRecords = max(1, maxRecords)
    }

    func record(
        _ notification: ReadReceiptNotification,
        receiptMessageID: MessageHeader.ID,
        receivedAt: Date,
        accountID: BrevAccount.ID
    ) {
        guard let originalMessageID = normalizedMessageID(notification.originalMessageID) else {
            return
        }
        var records = allRecords(accountID: accountID)
        records.removeAll { $0.receiptMessageID == receiptMessageID }
        records.append(MessageReadReceiptNotificationRecord(
            originalMessageID: canonicalMessageID(originalMessageID),
            finalRecipient: notification.finalRecipient,
            disposition: notification.disposition,
            receiptMessageID: receiptMessageID,
            receivedAt: receivedAt
        ))
        records = Array(records.sorted { lhs, rhs in
            if lhs.receivedAt == rhs.receivedAt {
                return lhs.receiptMessageID > rhs.receiptMessageID
            }
            return lhs.receivedAt > rhs.receivedAt
        }.prefix(maxRecords))
        save(records, accountID: accountID)
    }

    func notifications(
        forOriginalMessageID originalMessageID: String,
        accountID: BrevAccount.ID
    ) -> [MessageReadReceiptNotificationRecord] {
        guard let normalized = normalizedMessageID(originalMessageID) else { return [] }
        return allRecords(accountID: accountID)
            .filter { Self.normalizedMessageID($0.originalMessageID) == normalized }
            .sorted { lhs, rhs in
                if lhs.receivedAt == rhs.receivedAt {
                    return lhs.receiptMessageID > rhs.receiptMessageID
                }
                return lhs.receivedAt > rhs.receivedAt
            }
    }

    private func allRecords(accountID: BrevAccount.ID) -> [MessageReadReceiptNotificationRecord] {
        guard let data = defaults.data(forKey: key(accountID: accountID)) else { return [] }
        return (try? JSONDecoder().decode([MessageReadReceiptNotificationRecord].self, from: data)) ?? []
    }

    private func save(_ records: [MessageReadReceiptNotificationRecord], accountID: BrevAccount.ID) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: key(accountID: accountID))
    }

    private func key(accountID: BrevAccount.ID) -> String {
        "readReceiptNotifications.\(accountID)"
    }

    private static func normalizedMessageID(_ value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        if value.hasPrefix("<") {
            value.removeFirst()
        }
        if value.hasSuffix(">") {
            value.removeLast()
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func normalizedMessageID(_ value: String?) -> String? {
        Self.normalizedMessageID(value)
    }

    private func canonicalMessageID(_ value: String) -> String {
        "<\(value)>"
    }
}
