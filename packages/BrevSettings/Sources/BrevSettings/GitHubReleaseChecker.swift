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

// MARK: - Public API

/// Result state for a GitHub Releases version check.
public enum GitHubUpdateState: Equatable, Sendable {
    /// No check has been run yet.
    case idle
    /// A network check is in progress.
    case checking
    /// The installed version is current.
    case upToDate(installedVersion: String)
    /// A newer version is available.
    case updateAvailable(latestVersion: String, releaseNotesURL: URL?, publishedAt: Date?)
    /// The check failed (network error, API error, etc.).
    case failed(message: String)
}

/// Lightweight GitHub Releases version checker.
///
/// Call `check(throttleInterval:)` to fetch the latest release.
/// A 12-hour throttle prevents hammering the API; pass `throttleInterval: 0`
/// for forced manual checks. The checker makes exactly one HTTPS request to
/// `api.github.com` per non-throttled invocation and stores no other data.
///
/// Privacy: no credentials, no request body, no telemetry. The GitHub
/// Releases API is public and unauthenticated for public repositories.
public struct GitHubReleaseChecker: Sendable {
    static let brevRepository = "henrikogaard/brev"

    /// The repository in `owner/repo` format, e.g. `"henrikogaard/brev"`.
    public let repository: String

    /// Key used to persist the last-check date in `UserDefaults`.
    public enum Key {
        public static let lastCheckDate = "githubRelease.lastCheckDate"
        public static let cachedLatestVersion = "githubRelease.latestVersion"
        public static let cachedReleaseURL = "githubRelease.releaseURL"
    }

    public init(repository: String) {
        self.repository = repository
    }

    /// Checks GitHub for the latest release.
    ///
    /// - Parameter installedVersion: The app's current version string (from `CFBundleShortVersionString`).
    /// - Parameter throttleInterval: Seconds between automatic checks. Pass `0` to force a check regardless.
    /// - Parameter defaults: Persistence store for throttle state. Defaults to `UserDefaults.standard`.
    /// - Returns: The new `GitHubUpdateState`.
    public func check(
        installedVersion: String,
        throttleInterval: TimeInterval = 43200, // 12 hours
        defaults: UserDefaults = .standard
    ) async -> GitHubUpdateState {
        if throttleInterval > 0, let lastCheck = defaults.object(forKey: Key.lastCheckDate) as? Date {
            if Date().timeIntervalSince(lastCheck) < throttleInterval {
                // Within throttle window — return cached state if available.
                return cachedState(installedVersion: installedVersion, defaults: defaults)
            }
        }

        let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed(message: String(localized: "Unexpected response type from GitHub.", bundle: .module))
            }
            if http.statusCode == 404 {
                // No releases published yet.
                defaults.set(Date(), forKey: Key.lastCheckDate)
                defaults.removeObject(forKey: Key.cachedLatestVersion)
                return .upToDate(installedVersion: installedVersion)
            }
            guard (200 ..< 300).contains(http.statusCode) else {
                return .failed(message: String(localized: "GitHub API returned HTTP \(http.statusCode).", bundle: .module))
            }
            let release = try JSONDecoder().decode(GitHubReleaseDTO.self, from: data)
            defaults.set(Date(), forKey: Key.lastCheckDate)
            let latestVersion = release.normalizedTagName
            defaults.set(latestVersion, forKey: Key.cachedLatestVersion)
            if let htmlURL = release.htmlURL {
                defaults.set(htmlURL.absoluteString, forKey: Key.cachedReleaseURL)
            }
            if Self.isNewer(latestVersion, than: installedVersion) {
                return .updateAvailable(
                    latestVersion: latestVersion,
                    releaseNotesURL: release.htmlURL,
                    publishedAt: release.publishedAt
                )
            }
            return .upToDate(installedVersion: installedVersion)
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private func cachedState(installedVersion: String, defaults: UserDefaults) -> GitHubUpdateState {
        guard let latestVersion = defaults.string(forKey: Key.cachedLatestVersion) else {
            return .idle
        }
        let releaseURL = (defaults.string(forKey: Key.cachedReleaseURL)).flatMap(URL.init(string:))
        if Self.isNewer(latestVersion, than: installedVersion) {
            return .updateAvailable(
                latestVersion: latestVersion,
                releaseNotesURL: releaseURL,
                publishedAt: nil
            )
        }
        return .upToDate(installedVersion: installedVersion)
    }

    /// Returns `true` when `candidate` is strictly newer than `installed`
    /// using Semantic Versioning precedence. A leading `v` and build metadata
    /// are ignored; pre-release identifiers still participate in ordering.
    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        guard let candidate = ComparableVersion(candidate),
              let installed = ComparableVersion(installed)
        else { return false }
        return candidate > installed
    }

    private struct ComparableVersion: Comparable {
        private enum Identifier: Comparable {
            case numeric(Int)
            case text(String)

            static func < (lhs: Identifier, rhs: Identifier) -> Bool {
                switch (lhs, rhs) {
                case (.numeric(let left), .numeric(let right)):
                    return left < right
                case (.numeric, .text):
                    return true
                case (.text, .numeric):
                    return false
                case (.text(let left), .text(let right)):
                    return left < right
                }
            }
        }

        private let core: [Int]
        private let preRelease: [Identifier]

        init?(_ rawValue: String) {
            var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("v") || value.hasPrefix("V") {
                value.removeFirst()
            }
            guard let withoutBuildMetadata = value.split(
                separator: "+",
                maxSplits: 1,
                omittingEmptySubsequences: false
            ).first else { return nil }
            let pieces = withoutBuildMetadata.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawCore = pieces.first else { return nil }
            let coreParts = rawCore.split(separator: ".", omittingEmptySubsequences: false)
            guard !coreParts.isEmpty,
                  coreParts.allSatisfy({ Int($0) != nil })
            else { return nil }
            core = coreParts.map { Int($0)! }
            if pieces.count == 2 {
                let identifiers = pieces[1].split(separator: ".", omittingEmptySubsequences: false)
                guard !identifiers.isEmpty,
                      identifiers.allSatisfy({ !$0.isEmpty })
                else { return nil }
                preRelease = identifiers.map { identifier in
                    Int(identifier).map(Identifier.numeric) ?? .text(String(identifier))
                }
            } else {
                preRelease = []
            }
        }

        static func < (lhs: ComparableVersion, rhs: ComparableVersion) -> Bool {
            let count = max(lhs.core.count, rhs.core.count)
            for index in 0 ..< count {
                let left = index < lhs.core.count ? lhs.core[index] : 0
                let right = index < rhs.core.count ? rhs.core[index] : 0
                if left != right { return left < right }
            }

            switch (lhs.preRelease.isEmpty, rhs.preRelease.isEmpty) {
            case (true, true):
                return false
            case (true, false):
                return false
            case (false, true):
                return true
            case (false, false):
                for index in 0 ..< max(lhs.preRelease.count, rhs.preRelease.count) {
                    guard index < lhs.preRelease.count else { return true }
                    guard index < rhs.preRelease.count else { return false }
                    let left = lhs.preRelease[index]
                    let right = rhs.preRelease[index]
                    if left != right { return left < right }
                }
                return false
            }
        }
    }
}

// MARK: - DTO

private struct GitHubReleaseDTO: Decodable {
    let tagName: String
    let htmlURL: URL?
    let publishedAt: Date?
    let prerelease: Bool
    let draft: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case prerelease
        case draft
    }

    /// Tag stripped of a leading `v`, e.g. `"v1.2.3"` → `"1.2.3"`.
    var normalizedTagName: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        htmlURL = try container.decodeIfPresent(URL.self, forKey: .htmlURL)
        prerelease = try container.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false
        draft = try container.decodeIfPresent(Bool.self, forKey: .draft) ?? false

        // publishedAt is ISO 8601 with fractional seconds optional.
        if let raw = try container.decodeIfPresent(String.self, forKey: .publishedAt) {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            publishedAt = iso.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        } else {
            publishedAt = nil
        }
    }
}
