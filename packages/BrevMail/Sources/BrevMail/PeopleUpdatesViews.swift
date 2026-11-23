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

import BrevAvatars
import BrevBackend
import BrevDesign
import BrevThemes
import SwiftUI

/// Pill-style tabs for the two-way People / Updates / All inbox split (#295).
struct PeopleUpdatesTabBar: View {
    @Environment(\.brevTheme) private var theme
    @Binding var activeTab: InboxSplitTab
    let counts: PeopleUpdatesCounts

    private var platform: MessageListSearchFieldPlatform {
        #if os(iOS)
        .iOS
        #else
        .macOS
        #endif
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrevSpacing.xs) {
                ForEach(InboxSplitTab.allCases) { tab in
                    tabButton(tab)
                }
            }
            .padding(.horizontal, BrevSpacing.md)
        }
        .frame(height: InboxCategoryBarPresentation.height(platform: platform))
        #if os(iOS)
            .background(BrevWindowSurfaceBackground(role: .content))
        #endif
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(BrevSeparator.color(for: theme))
                    .frame(height: 0.5)
            }
            .mailDenseListChromeDynamicType()
    }

    private func count(for tab: InboxSplitTab) -> Int {
        switch tab {
        case .people: counts.peopleCount
        case .updates: counts.updatesCount
        case .all: counts.allCount
        }
    }

    private func tabButton(_ tab: InboxSplitTab) -> some View {
        let isSelected = activeTab == tab
        let tabCount = count(for: tab)
        return Button {
            activeTab = tab
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: tab.title)
                    .brevFont(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                if tab != .all || tabCount > 0 {
                    Text(verbatim: "\(tabCount)")
                        .brevFont(.caption)
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? theme.textSecondary.color : theme.textTertiary.color)
                }
            }
            .foregroundStyle(isSelected ? theme.textPrimary.color : theme.textSecondary.color)
            .padding(.horizontal, BrevSpacing.sm)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(isSelected ? theme.bgTertiary.color : Color.clear)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tab.title), \(tabCount)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Collapsed sender bundle row inside the Updates tab (#295), with disclosure
/// chevron to expand individual messages and one-click bundle archive.
struct UpdatesBundleRowView<ChildContent: View>: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 28

    let bundle: UpdatesSenderBundle
    let isExpanded: Bool
    let canArchive: Bool
    let onToggleExpanded: () -> Void
    let onArchiveBundle: () -> Void
    let onMoveSenderToPeople: () -> Void
    @ViewBuilder let childRows: () -> ChildContent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: BrevSpacing.sm) {
                Button(action: onToggleExpanded) {
                    HStack(spacing: BrevSpacing.sm) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .brevFont(.caption)
                            .foregroundStyle(theme.textTertiary.color)
                            .frame(width: 12)
                        Text(verbatim: InitialsAvatar.initials(
                            displayName: bundle.senderName,
                            email: bundle.senderEmail
                        ))
                        .brevFont(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.textSecondary.color)
                        .frame(width: avatarSize, height: avatarSize)
                        .background(Circle().fill(theme.bgTertiary.color))
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: bundle.summaryLine(locale: locale))
                                .brevFont(.callout)
                                .fontWeight(bundle.unreadCount > 0 ? .semibold : .regular)
                                .foregroundStyle(theme.textPrimary.color)
                                .lineLimit(1)
                            Text(verbatim: bundle.latestHeader.subject)
                                .brevFont(.caption)
                                .foregroundStyle(theme.textSecondary.color)
                                .lineLimit(1)
                        }
                        Spacer(minLength: BrevSpacing.xs)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if canArchive {
                    Button(action: onArchiveBundle) {
                        Image(systemName: "archivebox")
                            .brevFont(.callout)
                            .foregroundStyle(theme.textSecondary.color)
                            .padding(BrevSpacing.xs)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Archive bundle", bundle: .module))
                    .accessibilityLabel(String(localized: "Archive bundle", bundle: .module))
                }
            }
            .padding(.vertical, BrevSpacing.xs)
            .contextMenu {
                if canArchive {
                    Button(action: onArchiveBundle) {
                        Label(String(localized: "Archive bundle", bundle: .module), systemImage: "archivebox")
                    }
                }
                Button(action: onMoveSenderToPeople) {
                    Label(String(localized: "Move sender to People", bundle: .module), systemImage: "person.2")
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    childRows()
                }
                .padding(.leading, BrevSpacing.lg)
            }
        }
    }
}
