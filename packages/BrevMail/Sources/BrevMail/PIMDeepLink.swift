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

import BrevCalendar
import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// A `brev://` deep link that targets one synced PIM record (#10).
///
/// Event and contact links carry the cached record's stable ID, so a
/// link keeps working across relaunches as long as the record stays in
/// the sync cache — including after its source was removed, per the
/// kept-cache contract (ADR-0072).
public enum PIMDeepLink: Equatable, Sendable {
    /// `brev://event?id=<PIMEvent.ID>` — reveals the event in Calendar.
    case event(id: PIMEvent.ID)
    /// `brev://contact?id=<PIMContact.ID>` — reveals the contact in Contacts.
    case contact(id: PIMContact.ID)
    /// `brev://task?id=<PIMTask.ID>` — reveals the task in Tasks (#12).
    case task(id: PIMTask.ID)
}

/// Builds and parses `brev://event` / `brev://contact` URLs (#10).
///
/// The parser is strict: only the two known hosts produce a link and an
/// absent or blank `id` fails closed, so a malformed or foreign
/// `brev://` URL is discarded instead of guessing a target.
public enum PIMDeepLinkPolicy {
    /// The deep link that reopens one cached event.
    public static func url(forEventID id: PIMEvent.ID) -> URL? {
        url(host: "event", id: id)
    }

    /// The deep link that reopens one cached contact.
    public static func url(forContactID id: PIMContact.ID) -> URL? {
        url(host: "contact", id: id)
    }

    /// The deep link that reopens one cached task (#12).
    public static func url(forTaskID id: PIMTask.ID) -> URL? {
        url(host: "task", id: id)
    }

    /// Parses a `brev://` URL into a PIM deep link; nil for any other
    /// scheme, host, or a missing/blank `id` query item.
    public static func link(from url: URL) -> PIMDeepLink? {
        guard url.scheme?.lowercased() == "brev",
              let host = url.host?.lowercased(),
              let components = URLComponents(
                  url: url, resolvingAgainstBaseURL: false
              ),
              let rawID = components.queryItems?.first(where: {
                  $0.name == "id"
              })?.value
        else {
            return nil
        }
        let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }
        switch host {
        case "event":
            return .event(id: id)
        case "contact":
            return .contact(id: id)
        case "task":
            return .task(id: id)
        default:
            return nil
        }
    }

    private static func url(host: String, id: String) -> URL? {
        var components = URLComponents()
        components.scheme = "brev"
        components.host = host
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        return components.url
    }
}

/// Writes a deep link to the system pasteboard — the "Copy Link"
/// action on the event and contact detail panes.
enum PIMDeepLinkCopy {
    static func copy(_ url: URL) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = url.absoluteString
        #endif
    }
}
