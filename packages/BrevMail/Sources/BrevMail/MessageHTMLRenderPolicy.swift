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
    static var downloadImagesActionTitle: String { String(localized: "Download images", bundle: .module) }

    static func resolve(_ state: MessageRemoteContentRenderState) -> MessageRemoteContentPrivacyCopy {
        let report = state.report
        let title = report.hasLikelyTrackers
            ? String(localized: "Tracking pixels blocked", bundle: .module)
            : String(localized: "Remote content blocked", bundle: .module)
        return MessageRemoteContentPrivacyCopy(
            title: title,
            explanation: explanation(for: report),
            primaryActionTitle: downloadImagesActionTitle
        )
    }

    private static func explanation(for report: MessageRemoteContentAssetReport) -> String {
        let blockedSummary: String
        if report.hasLikelyTrackers {
            let trackerCount = report.likelyTrackerCount
            let trackerText = String(localized: "\(trackerCount) likely tracking pixels", bundle: .module)
            let otherAssetCount = report.assetCount - report.likelyTrackerCount
            if otherAssetCount > 0 {
                let otherAssetText = String(localized: "\(otherAssetCount) other remote assets", bundle: .module)
                blockedSummary = String(localized: "Brev blocked \(trackerText) and \(otherAssetText).", bundle: .module)
            } else {
                blockedSummary = String(localized: "Brev blocked \(trackerText).", bundle: .module)
            }
        } else {
            let assetCount = report.assetCount
            let assetText = String(localized: "\(assetCount) remote assets", bundle: .module)
            blockedSummary = String(localized: "Brev blocked \(assetText).", bundle: .module)
        }

        let hosts = hostSummary(report.hosts)
        return String(
            localized: "\(blockedSummary) Loading remote content would contact \(hosts), which can reveal your IP address and when you opened this message.",
            bundle: .module
        )
    }

    private static func hostSummary(_ hosts: [String]) -> String {
        guard !hosts.isEmpty else { return String(localized: "the remote hosts", bundle: .module) }
        if hosts.count == 1 {
            return hosts[0]
        }
        if hosts.count <= 3 {
            return list(hosts)
        }
        let leading = hosts.prefix(3).joined(separator: ", ")
        let remaining = hosts.count - 3
        return String(localized: "\(leading), and \(remaining) more hosts", bundle: .module)
    }

    private static func list(_ values: [String]) -> String {
        guard let last = values.last else { return "" }
        let leading = values.dropLast()
        if leading.isEmpty { return last }
        let first = leading[leading.startIndex]
        if leading.count == 1 {
            return String(localized: "\(first) and \(last)", bundle: .module)
        }
        // Callers pass at most three hosts, so the list here is exactly three.
        let second = leading[leading.index(after: leading.startIndex)]
        return String(localized: "\(first), \(second), and \(last)", bundle: .module)
    }
}
