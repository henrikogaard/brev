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

import BrevDesign
import BrevThemes
import SwiftUI

public struct SettingsUpdateActions {
    public static let unavailable = SettingsUpdateActions(
        isManualCheckAvailable: false,
        checkForUpdates: {},
        settingsDidChange: { _ in }
    )

    public var isManualCheckAvailable: Bool
    public var checkForUpdates: @MainActor () -> Void
    public var settingsDidChange: @MainActor (UpdateSettings) -> Void

    public init(
        isManualCheckAvailable: Bool,
        checkForUpdates: @escaping @MainActor () -> Void,
        settingsDidChange: @escaping @MainActor (UpdateSettings) -> Void
    ) {
        self.isManualCheckAvailable = isManualCheckAvailable
        self.checkForUpdates = checkForUpdates
        self.settingsDidChange = settingsDidChange
    }

    @MainActor
    public func performManualCheckIfAvailable() {
        guard isManualCheckAvailable else { return }
        checkForUpdates()
    }
}

public enum GitHubReleaseCheckPolicy {
    public static let shouldRunOnSettingsOpen = false
}

struct UpdatesSection: View {
    @Environment(\.brevTheme) private var theme
    @State private var settings: UpdateSettings
    @State private var githubUpdateState: GitHubUpdateState = .idle

    private let settingsStore: SettingsPersistenceStore
    private let updateActions: SettingsUpdateActions
    /// The installed app version, sourced from CFBundleShortVersionString.
    private let installedVersion: String

    init(
        settingsStore: SettingsPersistenceStore = .standard,
        updateActions: SettingsUpdateActions = .unavailable,
        installedVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    ) {
        self.settingsStore = settingsStore
        self.updateActions = updateActions
        self.installedVersion = installedVersion
        _settings = State(initialValue: settingsStore.updateSettings())
    }

    var body: some View {
        SectionScaffold(
            title: String(localized: "Updates", bundle: .module),
            subtitle: String(localized: "Manage direct-download macOS update checks.", bundle: .module)
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.xl) {
                cadenceGroup
                channelGroup
                githubReleaseGroup
                manualCheckGroup
            }
        }
        .task {
            guard GitHubReleaseCheckPolicy.shouldRunOnSettingsOpen else { return }
            await runGitHubCheck(forced: false)
        }
    }

    private var cadenceGroup: some View {
        SettingsGroup(
            title: String(localized: "Check cadence", bundle: .module),
            subtitle: String(localized: "Choose when Brev checks the signed Sparkle appcast.", bundle: .module),
            symbolName: "clock.arrow.circlepath"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                SettingsPickerRow(
                    symbolName: "timer",
                    title: String(localized: "Update checks", bundle: .module),
                    subtitle: settings.cadence.subtitle,
                    selection: binding(for: \.cadence)
                ) {
                    ForEach(UpdateCheckCadence.allCases) { cadence in
                        Text(cadence.title).tag(cadence)
                    }
                }

                SettingsInfoCallout(
                    symbolName: "network",
                    message: String(
                        localized: "Update checks contact updates.brevmail.eu only for direct-download macOS builds.",
                        bundle: .module
                    ),
                    tone: .info
                )
            }
        }
    }

    private var channelGroup: some View {
        SettingsGroup(
            title: String(localized: "Release channel", bundle: .module),
            subtitle: String(localized: "Switch between stable and beta appcasts.", bundle: .module),
            symbolName: "point.3.connected.trianglepath.dotted"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                SettingsPickerRow(
                    symbolName: "shippingbox",
                    title: String(localized: "Channel", bundle: .module),
                    subtitle: settings.channel.appcastURL.absoluteString,
                    selection: binding(for: \.channel)
                ) {
                    ForEach(UpdateChannel.allCases) { channel in
                        Text(channel.title).tag(channel)
                    }
                }

                if settings.channel == .beta {
                    SettingsInfoCallout(
                        symbolName: "exclamationmark.triangle",
                        message: String(localized: "Beta updates may be less stable and are always opt-in.", bundle: .module),
                        tone: .warning
                    )
                }
            }
        }
    }

    private var githubReleaseGroup: some View {
        SettingsGroup(
            title: String(localized: "GitHub releases", bundle: .module),
            subtitle: String(localized: "Check the public GitHub release feed for the latest version.", bundle: .module),
            symbolName: "arrow.down.circle.dotted"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                githubUpdateStateView

                HStack(spacing: BrevSpacing.sm) {
                    Button {
                        Task { await runGitHubCheck(forced: true) }
                    } label: {
                        Label(
                            githubUpdateState == .checking ? String(localized: "Checking…", bundle: .module) : String(
                                localized: "Check now",
                                bundle: .module
                            ),
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(githubUpdateState == .checking)
                    Spacer(minLength: 0)
                }

                SettingsInfoCallout(
                    symbolName: "network",
                    message: String(
                        localized: "Checks api.github.com for the latest Brev release. Only runs when you choose Check now.",
                        bundle: .module
                    ),
                    tone: .info
                )
            }
        }
    }

    @ViewBuilder
    private var githubUpdateStateView: some View {
        switch githubUpdateState {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: BrevSpacing.sm) {
                ProgressView().controlSize(.small)
                Text("Checking for updates…", bundle: .module)
                    .brevFont(.body)
                    .foregroundStyle(theme.textSecondary.color)
            }
        case .upToDate(let version):
            Label(String(localized: "Brev \(version) is up to date.", bundle: .module), systemImage: "checkmark.circle.fill")
                .brevFont(.body)
                .foregroundStyle(theme.success.color)
        case .updateAvailable(let latest, let url, _):
            VStack(alignment: .leading, spacing: BrevSpacing.xs) {
                Label(String(localized: "Brev \(latest) is available.", bundle: .module), systemImage: "arrow.down.circle.fill")
                    .brevFont(.subheadline)
                    .foregroundStyle(theme.accent.color)
                if let url {
                    Link(String(localized: "View release notes →", bundle: .module), destination: url)
                        .brevFont(.body)
                        .foregroundStyle(theme.accent.color)
                }
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .brevFont(.caption)
                .foregroundStyle(theme.textSecondary.color)
        }
    }

    private var manualCheckGroup: some View {
        SettingsGroup(
            title: String(localized: "Sparkle", bundle: .module),
            subtitle: String(localized: "Ask Sparkle to check the selected appcast now.", bundle: .module),
            symbolName: "arrow.down.circle"
        ) {
            VStack(alignment: .leading, spacing: BrevSpacing.md) {
                Button {
                    updateActions.performManualCheckIfAvailable()
                } label: {
                    Label(String(localized: "Check for Updates", bundle: .module), systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent.color)
                .disabled(!updateActions.isManualCheckAvailable)

                if !updateActions.isManualCheckAvailable {
                    SettingsInfoCallout(
                        symbolName: "lock",
                        message: String(
                            localized: "This build is missing direct-download Sparkle configuration, so update checks are disabled.",
                            bundle: .module
                        ),
                        tone: .warning
                    )
                }
            }
        }
    }

    private func binding<Value>(
        for keyPath: WritableKeyPath<UpdateSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { newValue in
                settings[keyPath: keyPath] = newValue
                settingsStore.save(settings)
                updateActions.settingsDidChange(settings)
            }
        )
    }

    private func runGitHubCheck(forced: Bool) async {
        guard githubUpdateState != .checking else { return }
        githubUpdateState = .checking
        let checker = GitHubReleaseChecker(repository: GitHubReleaseChecker.brevRepository)
        let state = await checker.check(
            installedVersion: installedVersion,
            throttleInterval: forced ? 0 : 43200
        )
        githubUpdateState = state
    }
}
