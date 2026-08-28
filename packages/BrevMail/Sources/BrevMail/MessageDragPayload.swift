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

struct SourceMessageDragPayload: Codable, Equatable, Hashable, Sendable {
    private static let prefix = "brev.source-message.v1:"

    let sourceID: MailSourceID
    let messageID: MessageHeader.ID

    var encodedRepresentation: String {
        guard let data = try? JSONEncoder().encode(self) else {
            return messageID
        }
        return Self.prefix + data.base64EncodedString()
    }

    init(sourceID: MailSourceID, messageID: MessageHeader.ID) {
        self.sourceID = sourceID
        self.messageID = messageID
    }

    init?(encodedRepresentation: String) {
        guard encodedRepresentation.hasPrefix(Self.prefix) else { return nil }
        let encodedPayload = String(encodedRepresentation.dropFirst(Self.prefix.count))
        guard let data = Data(base64Encoded: encodedPayload),
              let payload = try? JSONDecoder().decode(Self.self, from: data)
        else { return nil }
        self = payload
    }

    static func isEncodedPayload(_ representation: String) -> Bool {
        representation.hasPrefix(prefix)
    }
}

enum MessageDropRoute: Equatable, Sendable {
    case plain(messageIDs: [MessageHeader.ID])
    case source(sourceID: MailSourceID, messageIDs: [MessageHeader.ID])
}

enum MessageDropRoutingPolicy {
    static func route(
        _ representations: [String],
        destinationSourceID: MailSourceID?,
        selectedSourceID: MailSourceID?
    ) -> MessageDropRoute? {
        guard !representations.isEmpty else { return nil }
        var sourcePayloads: [SourceMessageDragPayload] = []
        var plainMessageIDs: [MessageHeader.ID] = []

        for representation in representations {
            if let payload = SourceMessageDragPayload(encodedRepresentation: representation) {
                sourcePayloads.append(payload)
            } else if SourceMessageDragPayload.isEncodedPayload(representation) {
                return nil
            } else {
                plainMessageIDs.append(representation)
            }
        }

        if !sourcePayloads.isEmpty {
            guard plainMessageIDs.isEmpty,
                  let sourceID = sourcePayloads.first?.sourceID,
                  sourcePayloads.allSatisfy({ $0.sourceID == sourceID }),
                  destinationSourceID == nil || destinationSourceID == sourceID
            else { return nil }
            return .source(
                sourceID: sourceID,
                messageIDs: sourcePayloads.map(\.messageID)
            )
        }

        guard !plainMessageIDs.isEmpty else { return nil }
        guard let destinationSourceID else {
            return .plain(messageIDs: plainMessageIDs)
        }
        if let selectedSourceID, selectedSourceID != destinationSourceID {
            return nil
        }
        return .source(
            sourceID: selectedSourceID ?? destinationSourceID,
            messageIDs: plainMessageIDs
        )
    }
}
