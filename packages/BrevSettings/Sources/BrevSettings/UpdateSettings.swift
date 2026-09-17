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

public struct UpdateSettings: Equatable, Sendable, Codable {
    public enum Key {
        public static let cadence = "updates.cadence"
    }

    public var cadence: UpdateCheckCadence

    public static let defaults = UpdateSettings(
        cadence: .oncePerLaunch
    )

    public init(
        cadence: UpdateCheckCadence = Self.defaults.cadence
    ) {
        self.cadence = cadence
    }

    public var automaticallyChecksForUpdates: Bool {
        cadence != .manual
    }

    public var startsUpdaterOnLaunch: Bool {
        cadence != .manual
    }

    public var scheduledCheckInterval: TimeInterval {
        cadence.scheduledCheckInterval
    }

    public static func load(from defaults: UserDefaults = .standard) -> UpdateSettings {
        // `updates.channel` was removed with the Beta channel (ADR-0080); a
        // stored value is intentionally left unread.
        UpdateSettings(
            cadence: enumValue(
                UpdateCheckCadence.self,
                for: Key.cadence,
                default: Self.defaults.cadence,
                defaults: defaults
            )
        )
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(cadence.rawValue, forKey: Key.cadence)
    }

    private static func enumValue<T>(
        _ type: T.Type,
        for key: String,
        default defaultValue: T,
        defaults: UserDefaults
    ) -> T where T: RawRepresentable, T.RawValue == String {
        guard let raw = defaults.string(forKey: key),
              let value = T(rawValue: raw) else {
            return defaultValue
        }
        return value
    }
}

public enum UpdateCheckCadence: String, CaseIterable, Identifiable, Sendable, Codable {
    case oncePerLaunch
    case weekly
    case manual

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .oncePerLaunch: return String(localized: "Once per launch", bundle: .module)
        case .weekly: return String(localized: "Weekly", bundle: .module)
        case .manual: return String(localized: "Manual", bundle: .module)
        }
    }

    var subtitle: String {
        switch self {
        case .oncePerLaunch:
            return String(localized: "Check the direct-download update feed when Brev opens.", bundle: .module)
        case .weekly:
            return String(localized: "Let Sparkle check in the background about once a week.", bundle: .module)
        case .manual:
            return String(localized: "Only check when you choose Check for Updates.", bundle: .module)
        }
    }

    var scheduledCheckInterval: TimeInterval {
        switch self {
        case .oncePerLaunch:
            return 86400
        case .weekly:
            return 604_800
        case .manual:
            return 0
        }
    }
}

/// Build-time release ring (ADR-0080). Stable and Nightly are separate apps
/// with separate feeds; there is no in-app ring switch.
public enum UpdateRing: String, Sendable, Codable, CaseIterable {
    case stable
    case nightly

    public var title: String {
        switch self {
        case .stable: return String(localized: "Stable", bundle: .module)
        case .nightly: return String(localized: "Nightly", bundle: .module)
        }
    }

    /// One-line description shown under the ring name in Settings.
    public var subtitle: String {
        switch self {
        case .stable:
            return String(localized: "Updates come from tagged releases.", bundle: .module)
        case .nightly:
            return String(localized: "Built from main every night. Expect rough edges.", bundle: .module)
        }
    }

    /// Default appcast for the ring, served from GitHub Pages.
    public var appcastURL: URL {
        switch self {
        case .stable:
            return URL(string: "https://henrikogaard.github.io/brev/appcast.xml")!
        case .nightly:
            return URL(string: "https://henrikogaard.github.io/brev/appcast-nightly.xml")!
        }
    }

    /// Where to download the other ring's app.
    public var otherRingDownloadURL: URL {
        switch self {
        case .stable:
            return URL(string: "https://github.com/henrikogaard/brev/releases/tag/nightly")!
        case .nightly:
            return URL(string: "https://github.com/henrikogaard/brev/releases/latest")!
        }
    }
}

public enum UpdatePlatform: String, Sendable, Codable {
    case macOS
    case iOS
}

public enum UpdateDistribution: String, Sendable {
    case directDownload
    case appStore
    case testFlight
    case unknown
}

public struct UpdateBuildConfiguration: Equatable, Sendable {
    public var platform: UpdatePlatform
    public var distribution: UpdateDistribution
    public var feedURL: URL?
    public var publicEDKey: String?
    public var localAppcastURL: URL?
    public var ring: UpdateRing

    public init(
        platform: UpdatePlatform,
        distribution: UpdateDistribution,
        feedURL: URL?,
        publicEDKey: String?,
        localAppcastURL: URL? = nil,
        ring: UpdateRing = .stable
    ) {
        self.platform = platform
        self.distribution = distribution
        self.feedURL = feedURL
        self.publicEDKey = publicEDKey
        self.localAppcastURL = localAppcastURL
        self.ring = ring
    }

    public init(
        infoDictionary: [String: Any],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        platform: UpdatePlatform
    ) {
        let distributionValue = infoDictionary["BRDistributionChannel"] as? String
        let feedValue = infoDictionary["SUFeedURL"] as? String
        let publicKeyValue = infoDictionary["SUPublicEDKey"] as? String
        let ringValue = infoDictionary["BRReleaseRing"] as? String
        let localAppcastValue = environment["BREV_LOCAL_APPCAST_URL"]
            ?? infoDictionary["BRLocalAppcastURL"] as? String

        self.init(
            platform: platform,
            distribution: UpdateDistribution(infoPlistValue: distributionValue),
            feedURL: feedValue.flatMap(URL.init(string:)),
            publicEDKey: publicKeyValue,
            localAppcastURL: Self.localAppcastURL(from: localAppcastValue),
            ring: UpdateRing(rawValue: ringValue ?? "") ?? .stable
        )
    }

    public var hasConfiguredPublicEDKey: Bool {
        guard let publicEDKey else { return false }
        let trimmed = publicEDKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && !trimmed.contains("$(")
            && !trimmed.localizedCaseInsensitiveContains("placeholder")
    }

    public var canInitializeSparkle: Bool {
        platform == .macOS
            && distribution == .directDownload
            && feedURL != nil
            && hasConfiguredPublicEDKey
    }

    /// Resolved feed: the QA loopback override wins, then the plist feed,
    /// then the ring's default GitHub Pages appcast (ADR-0080).
    public var appcastURL: URL {
        localAppcastURL ?? feedURL ?? ring.appcastURL
    }

    private static func localAppcastURL(from value: String?) -> URL? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(),
              host == "localhost" || host == "::1" || isIPv4Loopback(host) else {
            return nil
        }
        return url
    }

    private static func isIPv4Loopback(_ host: String) -> Bool {
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4,
              octets[0] == "127" else {
            return false
        }
        return octets.allSatisfy { octet in
            guard let value = Int(octet) else { return false }
            return (0 ... 255).contains(value)
        }
    }
}

private extension UpdateDistribution {
    init(infoPlistValue: String?) {
        switch infoPlistValue {
        case "direct-download":
            self = .directDownload
        case "app-store":
            self = .appStore
        case "testflight":
            self = .testFlight
        default:
            self = .unknown
        }
    }
}
