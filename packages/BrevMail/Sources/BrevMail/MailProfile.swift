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

/// A local saved workspace that filters which mail sources are visible.
///
/// Profiles are presentation state only: switching profiles does not
/// disconnect accounts, switch backend auth state, or mutate provider
/// configuration. The same source can appear in any number of profiles.
public struct MailProfile: Identifiable, Equatable, Hashable, Codable, Sendable {
    public static let allMailboxesID = "__brev_all_mailboxes"

    public var id: String
    public var name: String
    public var sourceIDs: [MailSourceID]
    public var isSystem: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        sourceIDs: [MailSourceID],
        isSystem: Bool = false
    ) {
        self.id = id
        self.name = name
        self.sourceIDs = sourceIDs
        self.isSystem = isSystem
    }

    public static func allMailboxes(sourceIDs: [MailSourceID]) -> MailProfile {
        MailProfile(
            id: allMailboxesID,
            name: "All Mailboxes",
            sourceIDs: sourceIDs,
            isSystem: true
        )
    }
}

enum MailProfileStorage {
    static func decode(_ rawValue: String) -> [MailProfile] {
        guard let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([MailProfile].self, from: data)
        else { return [] }
        return decoded.filter { !$0.isSystem }
    }

    static func encode(_ profiles: [MailProfile]) -> String {
        let customProfiles = profiles.filter { !$0.isSystem }
        guard let data = try? JSONEncoder().encode(customProfiles),
              let rawValue = String(data: data, encoding: .utf8)
        else { return "[]" }
        return rawValue
    }
}

enum MailProfileMoveDirection: Sendable {
    case up
    case down
}

enum MailProfileSelectionPolicy {
    static func resolvedProfiles(
        customProfiles: [MailProfile],
        availableSourceIDs: [MailSourceID]
    ) -> [MailProfile] {
        let normalizedCustomProfiles = normalizedCustomProfiles(
            customProfiles,
            availableSourceIDs: availableSourceIDs
        )
        return [
            .allMailboxes(sourceIDs: availableSourceIDs),
        ] + normalizedCustomProfiles
    }

    static func normalizedCustomProfiles(
        _ customProfiles: [MailProfile],
        availableSourceIDs _: [MailSourceID]
    ) -> [MailProfile] {
        // Availability is transient. Only explicit profile edits remove membership.
        return customProfiles
            .filter { !$0.isSystem }
            .compactMap { profile in
                let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                let sourceIDs = orderedUnique(profile.sourceIDs)
                guard !sourceIDs.isEmpty else { return nil }
                return MailProfile(
                    id: profile.id,
                    name: name,
                    sourceIDs: sourceIDs,
                    isSystem: false
                )
            }
    }

    static func selectedProfileID(
        _ proposedID: MailProfile.ID,
        profiles: [MailProfile]
    ) -> MailProfile.ID {
        profiles.contains { $0.id == proposedID }
            ? proposedID
            : MailProfile.allMailboxesID
    }

    static func visibleSections(
        from sourceSections: [MailSourceSection],
        activeProfileID: MailProfile.ID,
        profiles: [MailProfile]
    ) -> [MailSourceSection] {
        let selectedID = selectedProfileID(activeProfileID, profiles: profiles)
        guard let profile = profiles.first(where: { $0.id == selectedID }) else {
            return sourceSections
        }
        if profile.isSystem {
            return sourceSections
        }
        let visibleIDs = Set(profile.sourceIDs)
        return sourceSections.filter { visibleIDs.contains($0.id) }
    }

    static func sourceIDs(
        for activeProfileID: MailProfile.ID,
        profiles: [MailProfile]
    ) -> Set<MailSourceID>? {
        let selectedID = selectedProfileID(activeProfileID, profiles: profiles)
        guard let profile = profiles.first(where: { $0.id == selectedID }),
              !profile.isSystem
        else { return nil }
        return Set(profile.sourceIDs)
    }

    static func moveCustomProfile(
        id: MailProfile.ID,
        direction: MailProfileMoveDirection,
        in profiles: [MailProfile]
    ) -> [MailProfile] {
        guard let index = profiles.firstIndex(where: { $0.id == id }),
              !profiles[index].isSystem
        else {
            return profiles
        }
        let destinationIndex: Int
        switch direction {
        case .up:
            destinationIndex = index - 1
        case .down:
            destinationIndex = index + 1
        }
        guard profiles.indices.contains(destinationIndex) else {
            return profiles
        }
        var movedProfiles = profiles
        movedProfiles.swapAt(index, destinationIndex)
        return movedProfiles
    }

    private static func orderedUnique(_ sourceIDs: [MailSourceID]) -> [MailSourceID] {
        var seen: Set<MailSourceID> = []
        var result: [MailSourceID] = []
        for sourceID in sourceIDs where seen.insert(sourceID).inserted {
            result.append(sourceID)
        }
        return result
    }
}
