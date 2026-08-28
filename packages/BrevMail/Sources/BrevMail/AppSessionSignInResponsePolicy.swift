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

struct AppSessionSignInRequest: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case interactive
        case demo
    }

    let id: Int
    let kind: Kind

    init(id: Int, kind: Kind = .interactive) {
        self.id = id
        self.kind = kind
    }
}

enum AppSessionSignInResponsePolicy {
    static func canApplyResponse(
        request: AppSessionSignInRequest,
        activeRequest: AppSessionSignInRequest?
    ) -> Bool {
        activeRequest == request
    }
}

struct AuthenticationTaskRequest: Equatable, Sendable {
    let id: Int
}

enum AuthenticationTaskResponsePolicy {
    static func canClear(
        completedRequest: AuthenticationTaskRequest,
        activeRequest: AuthenticationTaskRequest?
    ) -> Bool {
        activeRequest == completedRequest
    }
}
