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

/// Ties the local-rule renderer to the ManageSieve client: renders the
/// Brev-owned Sieve script from `rules` and uploads + activates it on the
/// server (#198). The transport is injected so the flow is testable without a
/// live ManageSieve server; the default uses the real network transport.
public struct ManageSieveRuleSync: Sendable {
    private let transportFactory: @Sendable () -> any ManageSieveSessionTransport

    public init(
        transportFactory: @escaping @Sendable () -> any ManageSieveSessionTransport = {
            NetworkManageSieveSessionTransport()
        }
    ) {
        self.transportFactory = transportFactory
    }

    /// Renders `rules` into a single Brev-owned Sieve script and makes it the
    /// active script on `server`. Returns the rendered plan (so callers can
    /// surface `unsupportedRules` to the user). Throws on any rejection.
    @discardableResult
    public func sync(
        rules: [ServerRule],
        server: MailServerSettings,
        username: String,
        password: String,
        scriptName: String = "brev-rules"
    ) async throws -> SieveScriptPlan {
        let plan = SieveScriptRenderer.renderBrevOwnedScript(rules: rules, scriptName: scriptName)
        let client = ManageSieveSessionClient(transport: transportFactory())
        try await client.uploadAndActivate(
            plan: plan,
            server: server,
            username: username,
            password: password
        )
        return plan
    }
}
