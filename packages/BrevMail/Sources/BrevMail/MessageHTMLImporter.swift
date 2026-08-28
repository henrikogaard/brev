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
import SwiftUI

/// Background actor that performs the expensive `NSAttributedString` HTML
/// parsing off the main thread. `NSAttributedString(data:options:)` with
/// `.html` documentType uses WebKit, which historically prefers the main
/// thread, but in practice background parsing works on iOS and macOS and
/// is used by many shipping apps. Keeping this in a dedicated actor ensures
/// the main thread stays free for UI interaction while a message body is
/// being converted to `AttributedString`.
actor MessageHTMLImportActor {
    /// Parses HTML into `NSAttributedString`, strips inline foreground and
    /// background colors so the active Brev theme owns text contrast, and
    /// returns the result. Returns `nil` for empty/oversized/unparseable
    /// input. Runs on the actor's executor — never the main thread.
    func importAttributedHTML(_ html: String) -> AttributedString? {
        guard !html.isEmpty else { return nil }
        guard html.utf8.count <= 1_048_576 else { return nil }
        guard let data = html.data(using: .utf8) else { return nil }

        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        guard let ns = try? NSAttributedString(
            data: data,
            options: options,
            documentAttributes: nil
        ) else { return nil }

        let mutable = NSMutableAttributedString(attributedString: ns)
        mutable.removeAttribute(
            .foregroundColor,
            range: NSRange(location: 0, length: mutable.length)
        )
        mutable.removeAttribute(
            .backgroundColor,
            range: NSRange(location: 0, length: mutable.length)
        )

        return AttributedString(mutable)
    }
}

enum MessageHTMLImporter {
    /// Shared background actor for HTML import work. Reused across call
    /// sites so concurrent message-body renders serialize through one
    /// off-main executor instead of spawning detached tasks per render.
    private static let actor = MessageHTMLImportActor()

    /// Imports an HTML payload through `NSAttributedString` and returns
    /// it as a SwiftUI `AttributedString` with inline foreground colors
    /// stripped so the active Brev theme owns text contrast.
    ///
    /// The expensive `NSAttributedString` HTML parsing runs on a
    /// dedicated background actor — never the main thread — so the UI
    /// stays responsive while a message body is being converted. Callers
    /// on the main actor can `await` this without blocking the UI.
    static func importAttributedHTML(_ html: String?) async -> AttributedString? {
        let interval = MailUIPerformanceDiagnostics.beginInterval("HTML Body Import")
        defer { MailUIPerformanceDiagnostics.endInterval(interval) }
        func finish(_ result: AttributedString?) -> AttributedString? {
            MailUIPerformanceDiagnostics.logHTMLImportFinished(
                resultPresent: result != nil,
                durationMilliseconds: MailUIPerformanceDiagnostics.durationMilliseconds(since: interval.startedAt)
            )
            return result
        }

        guard let html, !html.isEmpty else { return finish(nil) }
        let result = await actor.importAttributedHTML(html)
        return finish(result)
    }
}
