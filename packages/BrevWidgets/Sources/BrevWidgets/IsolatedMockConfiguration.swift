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

/// Bundle-level isolation policy shared by the app and App Group consumers.
public enum IsolatedMockConfiguration {
    private static let bundlePrefix = "eu.brevmail.brev.test.mock."

    /// Recognizes isolated identities even if their required marker is missing.
    public static func isRequested(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) -> Bool {
        info["BRIsolatedMock"] as? String == "1"
            || (info["CFBundleIdentifier"] as? String)?.hasPrefix(bundlePrefix) == true
    }

    /// Requires a Debug test bundle running in its own UUID-named sandbox home.
    public static func permitsLaunch(info: [String: Any], home: URL, isDebugBuild: Bool) -> Bool {
        guard isDebugBuild,
              info["BRIsolatedMock"] as? String == "1",
              info["BRBuildKind"] as? String == "test",
              let identifier = info["CFBundleIdentifier"] as? String,
              identifier.hasPrefix(bundlePrefix),
              UUID(uuidString: String(identifier.dropFirst(bundlePrefix.count))) != nil else {
            return false
        }
        return home.standardizedFileURL.resolvingSymlinksInPath().path
            .hasSuffix("/Library/Containers/\(identifier)/Data")
    }

    /// Rejects shared groups, network, iCloud, system-data and other permissions.
    public static func hasOnlySandboxEntitlement(_ entitlements: [String: Any]) -> Bool {
        entitlements.count == 1 && entitlements["com.apple.security.app-sandbox"] as? Bool == true
    }
}
