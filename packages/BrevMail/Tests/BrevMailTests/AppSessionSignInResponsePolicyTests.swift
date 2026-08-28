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

@testable import BrevMail
import Testing

@Suite("AppSessionSignInResponsePolicy")
struct AppSessionSignInResponsePolicyTests {
    @Test("matching active sign-in request can apply a sign-in response")
    func matchingActiveSignInRequestCanApplySignInResponse() {
        #expect(AppSessionSignInResponsePolicy.canApplyResponse(
            request: AppSessionSignInRequest(id: 1),
            activeRequest: AppSessionSignInRequest(id: 1)
        ))
    }

    @Test("changed or missing active sign-in request rejects stale sign-in response")
    func changedOrMissingActiveSignInRequestRejectsStaleSignInResponse() {
        let request = AppSessionSignInRequest(id: 1)

        #expect(!AppSessionSignInResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: AppSessionSignInRequest(id: 2)
        ))
        #expect(!AppSessionSignInResponsePolicy.canApplyResponse(
            request: request,
            activeRequest: nil
        ))
    }

    @Test("only the current authentication task can clear its reference")
    func onlyCurrentAuthenticationTaskCanClearItsReference() {
        let original = AuthenticationTaskRequest(id: 1)
        let replacement = AuthenticationTaskRequest(id: 2)

        #expect(AuthenticationTaskResponsePolicy.canClear(
            completedRequest: replacement,
            activeRequest: replacement
        ))
        #expect(!AuthenticationTaskResponsePolicy.canClear(
            completedRequest: original,
            activeRequest: replacement
        ))
        #expect(!AuthenticationTaskResponsePolicy.canClear(
            completedRequest: original,
            activeRequest: nil
        ))
    }
}
