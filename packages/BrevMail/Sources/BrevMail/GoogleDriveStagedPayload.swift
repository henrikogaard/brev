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
import Observation

/// The bytes staged for one Drive save (#14), shared by reference.
///
/// The parent flow, the shared save sheet, and its model all read the
/// same container, so clearing it on cancel, dismissal, source
/// invalidation, or success drops the staged copy everywhere instead of
/// leaving per-view copies behind. An upload already handed to the
/// transport keeps whatever buffer it captured; this is lifecycle
/// hygiene, not secure erasure.
@MainActor
@Observable
final class GoogleDriveStagedPayload {
    private(set) var filename: String?
    private(set) var mimeType: String?
    private(set) var bytes: Data?
    /// The Drive file the bytes came from, when the save started at one.
    private(set) var sourceFileID: String?

    init(
        filename: String? = nil,
        mimeType: String? = nil,
        bytes: Data? = nil,
        sourceFileID: String? = nil
    ) {
        self.filename = filename
        self.mimeType = mimeType
        self.bytes = bytes
        self.sourceFileID = sourceFileID
    }

    /// Whether a complete payload is available to upload.
    var isStaged: Bool {
        bytes != nil && !(filename ?? "").isEmpty && !(mimeType ?? "").isEmpty
    }

    func stage(
        filename: String,
        mimeType: String,
        bytes: Data,
        sourceFileID: String? = nil
    ) {
        self.filename = filename
        self.mimeType = mimeType
        self.bytes = bytes
        self.sourceFileID = sourceFileID
    }

    func clear() {
        filename = nil
        mimeType = nil
        bytes = nil
        sourceFileID = nil
    }
}
