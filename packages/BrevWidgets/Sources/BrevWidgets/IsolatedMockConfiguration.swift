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

import CoreFoundation
import Foundation

/// Bundle-level isolation policy shared by the app and App Group consumers.
public enum IsolatedMockConfiguration {
    private static let bundlePrefix = "eu.brevmail.brev.test.mock."

    /// Recognizes isolated identities even if their required marker is missing.
    public static func isRequested(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) -> Bool {
        info["BRIsolatedMock"] as? String == "1"
            || info["BRIsolatedMockProfile"] != nil
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

    /// Requires the exact permission allowlist for the signed bundle's QA profile.
    public static func hasExpectedEntitlements(_ entitlements: [String: Any], info: [String: Any]) -> Bool {
        guard let profile = (info["BRIsolatedMockProfile"] ?? "strict") as? String else { return false }
        var expected: Set<String> = ["com.apple.security.app-sandbox"]
        switch profile {
        case "strict": break
        case "content-qa":
            expected.formUnion([
                "com.apple.security.network.client", "com.apple.security.files.user-selected.read-only"
            ])
        default: return false
        }
        return Set(entitlements.keys) == expected && entitlements.values.allSatisfy {
            CFGetTypeID($0 as CFTypeRef) == CFBooleanGetTypeID() && $0 as? Bool == true
        }
    }
}
