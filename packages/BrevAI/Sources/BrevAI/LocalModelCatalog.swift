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

/// Curated metadata describing a downloadable, open-licensed local AI model (#304).
///
/// Brev never bundles model weights in the app binary and never contacts model hosts
/// until the user explicitly chooses to download a model in Settings.
public struct LocalModelDescriptor: Codable, Equatable, Hashable, Identifiable, Sendable {
    /// Stable catalog identifier used for storage directories and provider routing.
    public let id: String

    /// Human-readable model name shown in Settings.
    public let displayName: String

    /// Concise summary of the model's intended mail-assistance strengths.
    public let summary: String

    /// Compact parameter count label (for example `"3B"` or `"3.8B"`).
    public let parameterCountLabel: String

    /// Quantization format label (for example `"Q4_K_M"`).
    public let quantization: String

    /// Expected download size in bytes, shown before download and enforced as a safety cap.
    public let expectedByteCount: Int64

    /// SPDX license identifier for the model weights (for example `"Apache-2.0"` or `"MIT"`).
    public let licenseSPDX: String

    /// Strictly HTTPS source URL for user-initiated weight downloads.
    public let downloadURL: URL

    /// Expected lowercase 64-character SHA-256 hex digest verified before activating weights.
    public let sha256Hex: String

    /// Recommended minimum unified memory / RAM in GiB for smooth on-device inference.
    public let minimumMemoryGiB: Int

    /// Local filename stored inside the backup-excluded model directory.
    public let fileName: String

    /// Creates a local model catalog descriptor.
    public init(
        id: String,
        displayName: String,
        summary: String,
        parameterCountLabel: String,
        quantization: String,
        expectedByteCount: Int64,
        licenseSPDX: String,
        downloadURL: URL,
        sha256Hex: String,
        minimumMemoryGiB: Int,
        fileName: String
    ) {
        self.id = id
        self.displayName = displayName
        self.summary = summary
        self.parameterCountLabel = parameterCountLabel
        self.quantization = quantization
        self.expectedByteCount = expectedByteCount
        self.licenseSPDX = licenseSPDX
        self.downloadURL = downloadURL
        self.sha256Hex = sha256Hex.lowercased()
        self.minimumMemoryGiB = minimumMemoryGiB
        self.fileName = fileName
    }

    /// Hostname of the HTTPS download source shown to the user before downloading.
    public var sourceHost: String {
        downloadURL.host(percentEncoded: false) ?? downloadURL.host ?? downloadURL.absoluteString
    }

    /// Human-readable download size formatted using file byte counts.
    public var formattedByteCount: String {
        ByteCountFormatter.string(fromByteCount: expectedByteCount, countStyle: .file)
    }

    /// Whether this descriptor specifies a valid HTTPS URL, positive size, and well-formed SHA-256 digest.
    public var hasValidHTTPSDownloadURL: Bool {
        guard let scheme = downloadURL.scheme?.lowercased(),
              scheme == "https",
              let host = downloadURL.host,
              !host.isEmpty,
              expectedByteCount > 0,
              Self.isValidSHA256Hex(sha256Hex)
        else { return false }
        return true
    }

    /// Validates that a string is a 64-character hexadecimal SHA-256 digest.
    public static func isValidSHA256Hex(_ candidate: String) -> Bool {
        guard candidate.count == 64 else { return false }
        return candidate.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57) // 0-9
                || (byte >= 65 && byte <= 70) // A-F
                || (byte >= 97 && byte <= 102) // a-f
        }
    }
}

/// Curated catalog of small, open-licensed on-device models available for user-initiated download (#304).
public enum LocalModelCatalog {
    /// Default catalog model selected when creating a downloaded-model provider profile.
    public static let defaultModelID = "qwen2.5-3b-instruct-q4km"

    /// Curated open-weights models that run offline after explicit user download and SHA-256 verification.
    public static let curatedModels: [LocalModelDescriptor] = [
        LocalModelDescriptor(
            id: "qwen2.5-3b-instruct-q4km",
            displayName: "Qwen 2.5 3B Instruct",
            summary: "Balanced multilingual drafting, rewriting, and thread summaries.",
            parameterCountLabel: "3B",
            quantization: "Q4_K_M",
            expectedByteCount: 2_104_932_736,
            licenseSPDX: "Apache-2.0",
            downloadURL: URL(
                string: "https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf"
            )!,
            sha256Hex: "626b4a6678b86442240e33df819e00132d3ba7dddfe1cdc4fbb18b9a9f89614a",
            minimumMemoryGiB: 8,
            fileName: "qwen2.5-3b-instruct-q4_k_m.gguf"
        ),
        LocalModelDescriptor(
            id: "llama-3.2-3b-instruct-q4km",
            displayName: "Llama 3.2 3B Instruct",
            summary: "Fast everyday replies, tone adjustments, and concise summaries.",
            parameterCountLabel: "3B",
            quantization: "Q4_K_M",
            expectedByteCount: 2_019_377_696,
            licenseSPDX: "Llama-3.2",
            downloadURL: URL(
                string: "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf"
            )!,
            sha256Hex: "6c1a2b41161032677be168d354123594c0e6e67d2b9227c84f296ad037c728ff",
            minimumMemoryGiB: 8,
            fileName: "Llama-3.2-3B-Instruct-Q4_K_M.gguf"
        ),
        LocalModelDescriptor(
            id: "phi-4-mini-instruct-q4km",
            displayName: "Phi-4 Mini Instruct",
            summary: "Strong structured reasoning for longer mail threads and action extraction.",
            parameterCountLabel: "3.8B",
            quantization: "Q4_K_M",
            expectedByteCount: 2_491_875_008,
            licenseSPDX: "MIT",
            downloadURL: URL(
                string: "https://huggingface.co/bartowski/microsoft_Phi-4-mini-instruct-GGUF/resolve/main/microsoft_Phi-4-mini-instruct-Q4_K_M.gguf"
            )!,
            sha256Hex: "7f6f18e42f12e3f810bc79a8d2c7a480501c1125fd19d2b0d2c0a56a2b93e0e1",
            minimumMemoryGiB: 8,
            fileName: "microsoft_Phi-4-mini-instruct-Q4_K_M.gguf"
        )
    ]

    /// Returns the catalog descriptor matching `id`, if present.
    public static func model(id: String) -> LocalModelDescriptor? {
        curatedModels.first { $0.id == id }
    }
}
