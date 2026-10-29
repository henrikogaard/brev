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
import Foundation
import SwiftUI

struct AboutSectionInfoRow: Equatable {
    let label: String
    let value: String
}

enum AboutSectionPresentation {
    static let authorName = "Henrik Øgård"
    static let repositoryDisplayName = "henrikogaard/brev"
    static let repositoryURL = URL(string: "https://github.com/henrikogaard/brev")!

    static func infoRows(version: String) -> [AboutSectionInfoRow] {
        [
            AboutSectionInfoRow(label: String(localized: "Version", bundle: .module), value: version),
            AboutSectionInfoRow(label: String(localized: "License", bundle: .module), value: "MIT"),
            AboutSectionInfoRow(label: String(localized: "Author", bundle: .module), value: authorName)
        ]
    }
}

private struct SettingsAboutVersionKey: EnvironmentKey {
    static var defaultValue: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}

extension EnvironmentValues {
    var settingsAboutVersion: String {
        get { self[SettingsAboutVersionKey.self] }
        set { self[SettingsAboutVersionKey.self] = newValue }
    }
}

struct AboutSection: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.settingsAboutVersion) private var version
    @Binding private var showDeveloperSettings: Bool

    init(showDeveloperSettings: Binding<Bool> = .constant(false)) {
        _showDeveloperSettings = showDeveloperSettings
    }

    var body: some View {
        SectionScaffold(title: String(localized: "About", bundle: .module)) {
            SettingsGroup(
                title: String(localized: "About", bundle: .module),
                subtitle: "",
                symbolName: "info.circle"
            ) {
                SettingsRowStack {
                    ForEach(AboutSectionPresentation.infoRows(version: version), id: \.label) { item in
                        row(label: item.label, value: item.value)
                    }
                    linkRow(
                        label: String(localized: "Repository", bundle: .module),
                        title: AboutSectionPresentation.repositoryDisplayName,
                        destination: AboutSectionPresentation.repositoryURL
                    )
                }
            }
            SettingsGroup(
                title: String(localized: "Developer", bundle: .module),
                subtitle: String(
                    localized: "Show developer tools and plugin settings in the sidebar.",
                    bundle: .module
                ),
                symbolName: "hammer"
            ) {
                SettingsToggleRow(
                    symbolName: "hammer",
                    title: String(localized: "Show Developer Settings", bundle: .module),
                    subtitle: "",
                    isOn: $showDeveloperSettings
                )
            }
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .brevFont(.subheadline)
                .foregroundStyle(theme.textSecondary.color)
            Spacer()
            Text(value)
                .brevFont(.subheadline)
                .foregroundStyle(theme.textPrimary.color)
        }
    }

    private func linkRow(label: String, title: String, destination: URL) -> some View {
        HStack {
            Text(label)
                .brevFont(.subheadline)
                .foregroundStyle(theme.textSecondary.color)
            Spacer()
            Link(destination: destination) {
                Text(title)
                    .brevFont(.subheadline)
                    .foregroundStyle(theme.accent.color)
            }
        }
    }
}
