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
import BrevSettings

struct MailRetentionSweepTarget: Equatable, Sendable {
    let sourceID: MailSourceID
    let accountID: BrevAccount.ID
    let folderID: Folder.ID
    let retentionDays: Int?
    let keepsBodies: Bool
}

enum MailRetentionSweepPlan {
    static func shouldApplyRetention(syncHealth: AccountSyncHealth?) -> Bool {
        guard let syncHealth else { return true }
        guard syncHealth.state != .indexing else { return false }
        guard case .rebuilding = syncHealth.indexStatus else { return true }
        return false
    }

    static func targets(
        sourceSections: [MailSourceSection],
        fallbackSourceID: MailSourceID?,
        fallbackFolders: [Folder],
        settings: AccountMailboxSyncSettings
    ) -> [MailRetentionSweepTarget] {
        var targets: [MailRetentionSweepTarget] = []
        if sourceSections.isEmpty {
            if let fallbackSourceID {
                appendTargets(
                    forSourceID: fallbackSourceID,
                    folders: fallbackFolders,
                    settings: settings,
                    to: &targets
                )
            }
        } else {
            for section in sourceSections {
                appendTargets(
                    forSourceID: section.id,
                    folders: section.folders,
                    settings: settings,
                    to: &targets
                )
            }
        }
        return deduplicated(targets)
    }

    private static func appendTargets(
        forSourceID sourceID: MailSourceID,
        folders: [Folder],
        settings: AccountMailboxSyncSettings,
        to targets: inout [MailRetentionSweepTarget]
    ) {
        for folder in folders {
            let policy = settings.policy(for: folder.id)
            targets.append(MailRetentionSweepTarget(
                sourceID: sourceID,
                accountID: sourceID.accountID,
                folderID: folder.id,
                retentionDays: policy.retentionDays,
                keepsBodies: policy.keepsBodies
            ))
        }
    }

    private static func deduplicated(_ targets: [MailRetentionSweepTarget]) -> [MailRetentionSweepTarget] {
        var seen = Set<String>()
        return targets.filter { target in
            seen.insert("\(target.accountID)\u{1F}\(target.sourceID.mailboxID)\u{1F}\(target.folderID)").inserted
        }
    }
}
