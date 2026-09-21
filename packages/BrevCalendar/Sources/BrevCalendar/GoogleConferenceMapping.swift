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

/// Maps a Google Calendar `conferenceData` object onto the shared
/// PIMConference model (#13).
///
/// Shared by the sync adapter and the write service so a create
/// response renders identically to a synced record. Unknown
/// conference solutions keep their provider key and still expose
/// whatever entry points exist — the UI never assumes Meet.
enum GoogleConferenceMapping {
    /// Builds the conference record for an event payload.
    ///
    /// Prefers `conferenceData`; when that object is absent, a bare
    /// `hangoutLink` still produces a Meet record so legacy events
    /// stay joinable. A `conferenceData` without entry points (a
    /// pending create) still yields a record with its status.
    static func conference(from item: [String: Any]) -> PIMConference? {
        guard let conference = item["conferenceData"] as? [String: Any]
        else {
            guard let join = item["hangoutLink"] as? String,
                  !join.isEmpty else {
                return nil
            }
            return PIMConference(
                kind: .meet,
                providerKey: "hangoutsMeet",
                name: "Google Meet",
                joinURL: join
            )
        }

        var joinURL: String?
        var dialIns: [PIMConference.DialIn] = []
        for entry in conference["entryPoints"] as? [[String: Any]] ?? [] {
            let type = entry["entryPointType"] as? String
            let uri = entry["uri"] as? String
            let label = entry["label"] as? String
            let pin = entry["pin"] as? String
                ?? entry["accessCode"] as? String
            switch type {
            case "video":
                if joinURL == nil { joinURL = uri }
            case "phone":
                if let uri {
                    dialIns.append(
                        PIMConference.DialIn(
                            uri: uri,
                            label: label,
                            pin: pin
                        )
                    )
                }
            default:
                if joinURL == nil { joinURL = uri }
            }
        }
        if joinURL == nil,
           let fallback = item["hangoutLink"] as? String,
           !fallback.isEmpty {
            joinURL = fallback
        }

        let solution = conference["conferenceSolution"] as? [String: Any]
        let solutionKey = solution?["key"] as? [String: Any]
        // A pending create has no conferenceSolution yet — the
        // createRequest's key identifies the provider instead.
        let requestKey = (conference["createRequest"]
            as? [String: Any])?["conferenceSolutionKey"]
            as? [String: Any]
        let providerKey = (solutionKey?["type"] as? String)
            ?? (requestKey?["type"] as? String)
        let name = solution?["name"] as? String
        let kind: PIMConference.Kind =
            (providerKey?.localizedCaseInsensitiveContains("meet")
                    == true)
                || (joinURL?.localizedCaseInsensitiveContains(
                    "meet.google.com"
                ) == true)
                ? .meet
                : .other
        let status: PIMConference.Status? = {
            guard let statusDict = conference["status"]
                as? [String: Any],
                let code = statusDict["statusCode"] as? String
            else { return nil }
            switch code {
            case "pending": return .pending
            case "success": return .success
            case "failure": return .failure
            default: return nil
            }
        }()
        return PIMConference(
            kind: kind,
            providerKey: providerKey,
            name: name,
            joinURL: joinURL,
            dialIns: dialIns,
            status: status
        )
    }
}
