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

#if os(macOS)
@testable import BrevSettings
import Testing

/// ADR-0075 / Rule 7: only the release bundle may register as a login item.
/// `SMAppService` itself is never invoked from tests.
@Suite("LaunchAtLoginAvailability")
struct LaunchAtLoginAvailabilityTests {
    @Test("release bundle identifier is allowed")
    func releaseIdentifierIsAllowed() {
        #expect(LaunchAtLoginAvailability.isAvailable(bundleIdentifier: "eu.brevmail.brev"))
    }

    @Test("test-build identifiers and nil are rejected")
    func identifiersAreRejected() {
        #expect(!LaunchAtLoginAvailability.isAvailable(
            bundleIdentifier: "eu.brevmail.brev.test.d20260916"
        ))
        #expect(!LaunchAtLoginAvailability.isAvailable(bundleIdentifier: "eu.brevmail.brev.test"))
        #expect(!LaunchAtLoginAvailability.isAvailable(bundleIdentifier: "com.example.other"))
        #expect(!LaunchAtLoginAvailability.isAvailable(bundleIdentifier: nil))
    }
}
#endif
