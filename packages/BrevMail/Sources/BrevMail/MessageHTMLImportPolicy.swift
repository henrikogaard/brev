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

enum MessageHTMLImportPolicy {
    static func prepareForNativeImport(_ html: String, stripTrackingPixels: Bool) -> String {
        guard stripTrackingPixels else { return html }
        return MessageRemoteContentDetector.strippingLikelyTrackers(html).html
    }

    static func prepareForRemoteContentImport(
        _ html: String,
        allowRemoteContent: Bool,
        stripTrackingPixels: Bool
    ) -> String {
        guard allowRemoteContent else { return html }
        return prepareForNativeImport(html, stripTrackingPixels: stripTrackingPixels)
    }
}

struct MessageHTMLImportRequest: Equatable, Sendable {
    let generation: Int
    let messageKey: String
    let stripTrackingPixels: Bool

    func matchesCurrent(generation: Int, messageKey: String, stripTrackingPixels: Bool) -> Bool {
        self.generation == generation
            && self.messageKey == messageKey
            && self.stripTrackingPixels == stripTrackingPixels
    }
}
