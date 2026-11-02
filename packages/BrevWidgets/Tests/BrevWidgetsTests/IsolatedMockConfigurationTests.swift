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

@testable import BrevWidgets
import Foundation
import Testing

@Suite("Isolated macOS mock policy")
struct IsolatedMockConfigurationTests {
    private let identifier = "eu.brevmail.brev.test.mock.4DE6C7C8-FB92-4EE3-AFC1-B7C1A6E57948"

    private var info: [String: Any] {
        ["BRIsolatedMock": "1", "BRBuildKind": "test", "CFBundleIdentifier": identifier]
    }

    private var home: URL {
        URL(fileURLWithPath: "/Users/mock/Library/Containers/\(identifier)/Data")
    }

    @Test("Only a marked Debug test in its own sandbox may launch")
    func launchPolicy() {
        #expect(IsolatedMockConfiguration.isRequested(info: info))
        #expect(IsolatedMockConfiguration.permitsLaunch(info: info, home: home, isDebugBuild: true))
        #expect(!IsolatedMockConfiguration.permitsLaunch(info: info, home: home, isDebugBuild: false))
        for key in ["BRIsolatedMock", "BRBuildKind", "CFBundleIdentifier"] {
            var invalid = info
            invalid.removeValue(forKey: key)
            #expect(!IsolatedMockConfiguration.permitsLaunch(info: invalid, home: home, isDebugBuild: true))
        }
        var release = info
        release["BRBuildKind"] = "release"
        #expect(!IsolatedMockConfiguration.permitsLaunch(info: release, home: home, isDebugBuild: true))
    }

    @Test("Daily-driver, ordinary test and malformed mock identities cannot launch")
    func rejectsOtherIdentities() {
        for candidate in [
            "eu.brevmail.brev", "eu.brevmail.brev.nightly", "eu.brevmail.brev.test.d20261101",
            "eu.brevmail.brev.test.mock.", "eu.brevmail.brev.test.mock.not-a-uuid"
        ] {
            var invalid = info
            invalid["CFBundleIdentifier"] = candidate
            #expect(!IsolatedMockConfiguration.permitsLaunch(info: invalid, home: home, isDebugBuild: true))
        }
        #expect(!IsolatedMockConfiguration.isRequested(info: ["CFBundleIdentifier": "eu.brevmail.brev"]))
        #expect(IsolatedMockConfiguration.isRequested(info: ["CFBundleIdentifier": identifier]))
    }

    @Test("Alternate HOME and shared production containers are not isolation")
    func rejectsOtherHomes() {
        for path in [
            "/Users/mock", "/private/tmp/test-home", "/Users/mock/Library/Group Containers/group.eu.brevmail.brev",
            "/Users/mock/Library/Containers/eu.brevmail.brev/Data", home.path + "/child", home.path + "/../Other"
        ] {
            #expect(!IsolatedMockConfiguration.permitsLaunch(
                info: info, home: URL(fileURLWithPath: path), isDebugBuild: true
            ))
        }
    }

    @Test("Only the sandbox entitlement is accepted")
    func rejectsSharedOrExternalPermissions() {
        let sandbox: [String: Any] = ["com.apple.security.app-sandbox": true]
        #expect(IsolatedMockConfiguration.hasExpectedEntitlements(sandbox, info: info))
        #expect(IsolatedMockConfiguration.hasExpectedEntitlements(
            sandbox, info: ["BRIsolatedMockProfile": "strict"]
        ))
        #expect(!IsolatedMockConfiguration.hasExpectedEntitlements([:], info: info))
        #expect(!IsolatedMockConfiguration.hasExpectedEntitlements(["com.apple.security.app-sandbox": false], info: info))
        for extra in [
            "com.apple.security.application-groups", "com.apple.security.network.client",
            "com.apple.security.network.server", "com.apple.developer.ubiquity-kvstore-identifier",
            "com.apple.security.personal-information.addressbook", "keychain-access-groups"
        ] {
            var entitlements = sandbox
            entitlements[extra] = true
            #expect(!IsolatedMockConfiguration.hasExpectedEntitlements(entitlements, info: info))
        }
    }

    @Test("Content QA requires a matching marker and exactly the three approved permissions")
    func contentProfile() {
        var content = info
        content["BRIsolatedMockProfile"] = "content-qa"
        let permissions: [String: Any] = [
            "com.apple.security.app-sandbox": true,
            "com.apple.security.network.client": true,
            "com.apple.security.files.user-selected.read-only": true
        ]
        #expect(IsolatedMockConfiguration.isRequested(info: ["BRIsolatedMockProfile": "content-qa"]))
        #expect(IsolatedMockConfiguration.hasExpectedEntitlements(permissions, info: content))
        #expect(!IsolatedMockConfiguration.hasExpectedEntitlements(
            ["com.apple.security.app-sandbox": true], info: content
        ))
        #expect(IsolatedMockConfiguration.permitsLaunch(info: content, home: home, isDebugBuild: true))
        #expect(!IsolatedMockConfiguration.permitsLaunch(info: content, home: home, isDebugBuild: false))
        #expect(!IsolatedMockConfiguration.permitsLaunch(
            info: content, home: URL(fileURLWithPath: "/Users/mock"), isDebugBuild: true
        ))
        for key in ["BRIsolatedMock", "BRBuildKind", "CFBundleIdentifier"] {
            var invalid = content
            invalid.removeValue(forKey: key)
            #expect(!IsolatedMockConfiguration.permitsLaunch(info: invalid, home: home, isDebugBuild: true))
        }
        #expect(!IsolatedMockConfiguration.hasExpectedEntitlements(permissions, info: info))
        #expect(!IsolatedMockConfiguration.hasExpectedEntitlements(
            permissions, info: ["BRIsolatedMockProfile": "strict"]
        ))
        for key in permissions.keys {
            var invalid = permissions
            invalid.removeValue(forKey: key)
            #expect(!IsolatedMockConfiguration.hasExpectedEntitlements(invalid, info: content))
            for value: Any in [false, "true", 1, NSNumber(value: 1)] {
                invalid[key] = value
                #expect(!IsolatedMockConfiguration.hasExpectedEntitlements(invalid, info: content))
            }
        }
        for key in [
            "com.apple.security.application-groups", "com.apple.security.network.server",
            "com.apple.security.files.user-selected.read-write", "keychain-access-groups",
            "com.apple.security.personal-information.addressbook", "com.apple.security.personal-information.calendars",
            "com.apple.developer.ubiquity-kvstore-identifier"
        ] {
            var invalid = permissions
            invalid[key] = true
            #expect(!IsolatedMockConfiguration.hasExpectedEntitlements(invalid, info: content))
        }
        for marker: Any in ["unknown", "", 1, false] {
            var invalid = content
            invalid["BRIsolatedMockProfile"] = marker
            #expect(!IsolatedMockConfiguration.hasExpectedEntitlements(permissions, info: invalid))
            #expect(!IsolatedMockConfiguration.hasExpectedEntitlements(
                ["com.apple.security.app-sandbox": true], info: invalid
            ))
        }
    }

    @Test("Isolated widget and handoff storage never resolve the App Group")
    func suppressesAppGroupResolution() {
        var called = false
        let fakeDirectory = URL(fileURLWithPath: "/fake-group")
        let isolated = WidgetSnapshotStore.resolveDirectory(isolatedMock: true) {
            called = true
            return fakeDirectory
        }
        #expect(isolated == nil)
        #expect(!called)
        #expect(WidgetSnapshotStore.resolveDirectory(isolatedMock: false) { fakeDirectory } == fakeDirectory)
    }
}
