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
