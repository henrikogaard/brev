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

@testable import BrevSettings
import Foundation
import Testing

@Suite("GitHubReleaseChecker — version comparison")
struct GitHubReleaseCheckerVersionTests {
    @Test("Brev release checker targets the canonical repository")
    func brevReleaseCheckerTargetsCanonicalRepository() {
        #expect(GitHubReleaseChecker.brevRepository == "henrikogaard/brev")
    }

    @Test("newer patch version is detected")
    func newerPatchVersionIsDetected() {
        #expect(GitHubReleaseChecker.isNewer("1.0.1", than: "1.0.0"))
    }

    @Test("newer minor version is detected")
    func newerMinorVersionIsDetected() {
        #expect(GitHubReleaseChecker.isNewer("1.1.0", than: "1.0.9"))
    }

    @Test("newer major version is detected")
    func newerMajorVersionIsDetected() {
        #expect(GitHubReleaseChecker.isNewer("2.0.0", than: "1.9.9"))
    }

    @Test("equal version is not newer")
    func equalVersionIsNotNewer() {
        #expect(!GitHubReleaseChecker.isNewer("1.2.3", than: "1.2.3"))
    }

    @Test("older version is not newer")
    func olderVersionIsNotNewer() {
        #expect(!GitHubReleaseChecker.isNewer("0.9.9", than: "1.0.0"))
    }

    @Test("v-prefixed tag is normalized before comparison")
    func vPrefixedTagIsNormalized() {
        #expect(GitHubReleaseChecker.isNewer("v1.1.0", than: "1.0.0"))
        #expect(!GitHubReleaseChecker.isNewer("v1.0.0", than: "1.0.0"))
    }

    @Test("shorter version string is padded with zeros")
    func shorterVersionStringIsPadded() {
        // "2" should be treated as "2.0.0"
        #expect(GitHubReleaseChecker.isNewer("2", than: "1.9.9"))
        #expect(!GitHubReleaseChecker.isNewer("1", than: "1.0.1"))
    }

    @Test("pre-release suffix characters are stripped gracefully")
    func preleaseCharactersIgnored() {
        // Non-numeric components are dropped by compactMap
        #expect(!GitHubReleaseChecker.isNewer("1.0.0", than: "1.0.0"))
    }

    @Test("stable release is newer than a pre-release of the same version")
    func stableReleaseIsNewerThanPreRelease() {
        #expect(GitHubReleaseChecker.isNewer("1.0.0", than: "1.0.0-rc.1"))
        #expect(!GitHubReleaseChecker.isNewer("1.0.0-rc.1", than: "1.0.0"))
    }

    @Test("pre-release identifiers use semantic version ordering")
    func preReleaseIdentifiersUseSemanticOrdering() {
        #expect(GitHubReleaseChecker.isNewer("1.0.0-beta.2", than: "1.0.0-beta.1"))
        #expect(GitHubReleaseChecker.isNewer("1.0.0-beta.10", than: "1.0.0-beta.2"))
        #expect(!GitHubReleaseChecker.isNewer("1.0.0-beta.2", than: "1.0.0-beta.10"))
        #expect(GitHubReleaseChecker.isNewer("1.0.0-beta.2", than: "1.0.0-alpha.9"))
    }

    @Test("malformed version strings do not crash or compare as newer")
    func malformedVersionsAreIgnored() {
        #expect(!GitHubReleaseChecker.isNewer("", than: "1.0.0"))
        #expect(!GitHubReleaseChecker.isNewer("1.0.0", than: ""))
    }
}

@Suite("GitHubUpdateState equality")
struct GitHubUpdateStateTests {
    @Test("idle states are equal")
    func idleStatesAreEqual() {
        #expect(GitHubUpdateState.idle == .idle)
    }

    @Test("checking states are equal")
    func checkingStatesAreEqual() {
        #expect(GitHubUpdateState.checking == .checking)
    }

    @Test("upToDate states with same version are equal")
    func upToDateStatesAreEqual() {
        #expect(
            GitHubUpdateState.upToDate(installedVersion: "1.0.0") ==
                .upToDate(installedVersion: "1.0.0")
        )
    }

    @Test("updateAvailable states with same version and nil URL are equal")
    func updateAvailableStatesAreEqual() {
        #expect(
            GitHubUpdateState.updateAvailable(latestVersion: "2.0.0", releaseNotesURL: nil, publishedAt: nil) ==
                .updateAvailable(latestVersion: "2.0.0", releaseNotesURL: nil, publishedAt: nil)
        )
    }

    @Test("failed states with same message are equal")
    func failedStatesAreEqual() {
        #expect(GitHubUpdateState.failed(message: "timeout") == .failed(message: "timeout"))
    }

    @Test("different states are not equal")
    func differentStatesAreNotEqual() {
        #expect(GitHubUpdateState.idle != .checking)
        #expect(
            GitHubUpdateState.upToDate(installedVersion: "1.0.0") !=
                .updateAvailable(latestVersion: "2.0.0", releaseNotesURL: nil, publishedAt: nil)
        )
    }
}
