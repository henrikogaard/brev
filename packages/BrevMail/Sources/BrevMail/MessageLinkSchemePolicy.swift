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

/// Decides whether a link tapped inside untrusted message HTML may be handed to
/// the system URL opener. Message bodies are attacker-controlled, so links that
/// could execute code, render attacker HTML, or reach local resources must be
/// dropped rather than opened — even though the in-WebView navigation is always
/// cancelled and scripting is disabled, the opener still runs in the OS context.
enum MessageLinkSchemePolicy {
    /// Schemes explicitly approved for links extracted from untrusted mail.
    /// Keep this an allowlist: new OS handlers must not become reachable from
    /// message HTML merely because they are not yet known to be dangerous.
    static let allowedSchemes: Set<String> = ["http", "https", "mailto", "tel", "sms"]

    /// Whether a message-HTML link may be opened. A blocked or missing scheme
    /// returns `false`; a relative (schemeless) link can't be resolved without a
    /// base and is dropped.
    static func isOpenable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), !scheme.isEmpty else {
            return false
        }
        return allowedSchemes.contains(scheme)
    }

    /// Message HTML may contain communication links, but these invoke local
    /// handlers and therefore are never opened without a separate confirmation
    /// surface. The current reader denies them until such a surface exists.
    static func isDirectlyOpenable(_ url: URL) -> Bool {
        guard isOpenable(url), let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
