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
import BrevDesign
import Foundation
import SwiftUI

/// Account-scoped persisted pin identity. Legacy unscoped IDs remain untouched.
enum MailPinnedMessages {
    static let maximumCount = 500
    static let storageKey = "list.pinnedSourceMessageIDs.v2"

    static func key(sourceID: MailSourceID, messageID: MessageHeader.ID) -> String {
        let components = [sourceID.accountID, sourceID.mailboxID, messageID]
        let value = components.map { "\($0.utf8.count):\($0)" }.joined()
        return Data(value.utf8).base64EncodedString()
    }

    /// Message IDs pinned in `sourceID`, decoded from the stored keys once.
    /// Cheaper than encoding a key for every loaded header: work scales with
    /// the pin count (at most 500), not the folder size.
    static func messageIDs(in raw: String, sourceID: MailSourceID) -> Set<MessageHeader.ID> {
        guard !raw.isEmpty else { return [] }
        var ids = Set<MessageHeader.ID>()
        for line in raw.split(separator: "\n") {
            guard let data = Data(base64Encoded: String(line)),
                  let decoded = String(data: data, encoding: .utf8),
                  let components = lengthPrefixedComponents(decoded),
                  components.count == 3,
                  components[0] == sourceID.accountID,
                  components[1] == sourceID.mailboxID else { continue }
            ids.insert(components[2])
        }
        return ids
    }

    /// Inverse of the `"<utf8 length>:<value>"` concatenation in `key`.
    private static func lengthPrefixedComponents(_ value: String) -> [String]? {
        var bytes = Substring(value).utf8[...]
        var components: [String] = []
        while !bytes.isEmpty {
            guard let colon = bytes.firstIndex(of: UInt8(ascii: ":")),
                  let length = Int(String(decoding: bytes[..<colon], as: UTF8.self)),
                  length >= 0 else { return nil }
            let start = bytes.index(after: colon)
            guard let end = bytes.index(start, offsetBy: length, limitedBy: bytes.endIndex) else { return nil }
            components.append(String(decoding: bytes[start ..< end], as: UTF8.self))
            bytes = bytes[end...]
        }
        return components
    }

    static func toggling(sourceID: MailSourceID, messageID: MessageHeader.ID, in raw: String) throws -> String {
        var keys = Set(raw.split(separator: "\n").map(String.init))
        let id = key(sourceID: sourceID, messageID: messageID)
        if keys.contains(id) {
            keys.remove(id)
        } else {
            guard keys.count < maximumCount else { throw PinLimitReached() }
            keys.insert(id)
        }
        return keys.sorted().joined(separator: "\n")
    }
}

private struct PinLimitReached: LocalizedError {
    var errorDescription: String? {
        String(localized: "You can pin up to 500 messages. Unpin a message before adding another.", bundle: .module)
    }
}

/// Explains the legacy pins that cannot safely be assigned to an account automatically.
struct LegacyPinNotice: View {
    @AppStorage("list.pinnedMessageIDs") private var legacyPins = ""
    @AppStorage("list.legacyPinsNoticeDismissed") private var isDismissed = false

    var body: some View {
        if !legacyPins.isEmpty, !isDismissed {
            BrevInlineStatus(
                message: String(
                    localized: "Pins now belong to a mailbox. Pin older messages again to assign them; your old pin records have been kept.",
                    bundle: .module
                ),
                tone: .warning,
                actionTitle: nil,
                onAction: nil,
                onDismiss: { isDismissed = true }
            )
        }
    }
}
