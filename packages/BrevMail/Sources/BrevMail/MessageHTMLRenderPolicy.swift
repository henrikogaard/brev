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

enum MessageHTMLRenderPolicy {
    static func shouldImportAttributedHTML(
        _ html: String?,
        useRichRenderer: Bool,
        allowRemoteContent: Bool
    ) -> Bool {
        guard let html, !html.isEmpty else { return false }
        guard !useRichRenderer else { return false }
        return allowRemoteContent || !MessageRemoteContentDetector.hasRemoteAssets(html)
    }
}

struct MessageRemoteContentRenderState: Equatable, Sendable {
    let allowsRemoteContent: Bool
    let isBlocked: Bool
    let senderDomain: String?
    let report: MessageRemoteContentAssetReport
}

enum MessageRemoteContentRenderPolicy {
    static func state(
        html: String,
        senderEmail: String,
        allowRemoteContentDefault: Bool,
        loadOnce: Bool,
        policy: RemoteContentPolicy
    ) -> MessageRemoteContentRenderState {
        let report = MessageRemoteContentDetector.remoteAssetReport(html)
        let hosts = report.hosts
        let hasRemoteAssets = report.hasRemoteAssets
        let allowedByPolicy = policy.allows(senderEmail: senderEmail, resourceHost: nil)
            || (!hosts.isEmpty && hosts.allSatisfy { policy.allows(senderEmail: senderEmail, resourceHost: $0) })
        let allowsRemoteContent = !hasRemoteAssets
            || allowRemoteContentDefault
            || loadOnce
            || allowedByPolicy

        return MessageRemoteContentRenderState(
            allowsRemoteContent: allowsRemoteContent,
            isBlocked: hasRemoteAssets && !allowsRemoteContent,
            senderDomain: RemoteContentPolicy.senderDomain(for: senderEmail),
            report: report
        )
    }
}

struct MessageRemoteContentPrivacyCopy: Equatable, Sendable {
    let title: String
    let explanation: String
    let primaryActionTitle: String
}

enum MessageRemoteContentPrivacyPresentation {
    static let downloadImagesActionTitle = "Download images"

    static func resolve(_ state: MessageRemoteContentRenderState) -> MessageRemoteContentPrivacyCopy {
        let report = state.report
        let title = report.hasLikelyTrackers
            ? "Tracking pixels blocked"
            : "Remote content blocked"
        return MessageRemoteContentPrivacyCopy(
            title: title,
            explanation: explanation(for: report),
            primaryActionTitle: downloadImagesActionTitle
        )
    }

    private static func explanation(for report: MessageRemoteContentAssetReport) -> String {
        let blockedSummary: String
        if report.hasLikelyTrackers {
            let trackerText = pluralized(
                count: report.likelyTrackerCount,
                singular: "likely tracking pixel",
                plural: "likely tracking pixels"
            )
            let otherAssetCount = report.assetCount - report.likelyTrackerCount
            if otherAssetCount > 0 {
                let otherAssetText = pluralized(
                    count: otherAssetCount,
                    singular: "other remote asset",
                    plural: "other remote assets"
                )
                blockedSummary = "Brev blocked \(trackerText) and \(otherAssetText)."
            } else {
                blockedSummary = "Brev blocked \(trackerText)."
            }
        } else {
            let assetText = pluralized(
                count: report.assetCount,
                singular: "remote asset",
                plural: "remote assets"
            )
            blockedSummary = "Brev blocked \(assetText)."
        }

        let hosts = hostSummary(report.hosts)
        return "\(blockedSummary) Loading remote content would contact \(hosts), which can reveal your IP address and when you opened this message."
    }

    private static func pluralized(count: Int, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }

    private static func hostSummary(_ hosts: [String]) -> String {
        guard !hosts.isEmpty else { return "the remote hosts" }
        if hosts.count == 1 {
            return hosts[0]
        }
        if hosts.count <= 3 {
            return list(hosts)
        }
        return "\(hosts.prefix(3).joined(separator: ", ")), and \(hosts.count - 3) more host\(hosts.count - 3 == 1 ? "" : "s")"
    }

    private static func list(_ values: [String]) -> String {
        guard let last = values.last else { return "" }
        let leading = values.dropLast()
        if leading.isEmpty { return last }
        if leading.count == 1 { return "\(leading[leading.startIndex]) and \(last)" }
        return "\(leading.joined(separator: ", ")), and \(last)"
    }
}
