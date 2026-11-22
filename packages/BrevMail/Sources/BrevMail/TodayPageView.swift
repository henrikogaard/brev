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

/// The reader's empty state (#292): a calm overview of what needs you and
/// what you are waiting on, in place of "No message selected".
struct TodayPageView: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 28

    /// The user's display name, for the greeting.
    let displayName: String?
    /// Changes whenever the cached mail behind the digest may have changed.
    let refreshKey: Int
    /// Reads the digest from the local cache; nil keeps the current one.
    let load: () async -> TodayDigest?
    /// Opens one conversation in the reader.
    let onOpen: (TodayDigest.Row) -> Void
    /// Opens the assistant; nil hides the button (no AI configured).
    let onAsk: (() -> Void)?
    /// Starts sequential triage mode (#293); nil hides the button.
    let onStartTriage: (() -> Void)?
    /// The moment the page describes; fixed in snapshot tests.
    let now: Date

    @State private var digest: TodayDigest?

    /// - Parameter preloaded: A digest to show before `load` returns
    ///   (snapshot tests); nil shows the greeting alone until then.
    init(
        displayName: String?,
        refreshKey: Int,
        load: @escaping () async -> TodayDigest?,
        onOpen: @escaping (TodayDigest.Row) -> Void,
        onAsk: (() -> Void)?,
        onStartTriage: (() -> Void)? = nil,
        now: Date = .now,
        preloaded: TodayDigest? = nil
    ) {
        self.displayName = displayName
        self.refreshKey = refreshKey
        self.load = load
        self.onOpen = onOpen
        self.onAsk = onAsk
        self.onStartTriage = onStartTriage
        self.now = now
        _digest = State(initialValue: preloaded)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrevSpacing.xl) {
                header
                if let digest {
                    if !digest.waitingOnYou.isEmpty {
                        section(
                            title: String(localized: "Waiting on you", bundle: .module),
                            count: digest.waitingOnYouCount,
                            rows: digest.waitingOnYou
                        )
                    }
                    if !digest.youreWaitingOn.isEmpty {
                        section(
                            title: String(localized: "You're waiting on", bundle: .module),
                            count: digest.youreWaitingOnCount,
                            rows: digest.youreWaitingOn
                        )
                    }
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, BrevSpacing.xl)
            .padding(.vertical, BrevSpacing.xxl)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .task(id: refreshKey) {
            guard let loaded = await load(), !Task.isCancelled else { return }
            digest = loaded
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale)).uppercased(with: locale))
                .brevFont(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(theme.textTertiary.color)
            Text(verbatim: TodayGreeting.text(
                period: TodayGreeting.period(at: now),
                firstName: displayName.flatMap(TodayGreeting.firstName(from:))
            ))
            .brevFont(.largeTitle)
            .foregroundStyle(theme.textPrimary.color)
            .accessibilityAddTraits(.isHeader)
            if let digest {
                Text(verbatim: Self.summary(digest))
                    .brevFont(.body)
                    .foregroundStyle(theme.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if onAsk != nil || onStartTriage != nil {
                HStack(spacing: BrevSpacing.sm) {
                    if let onStartTriage {
                        Button(action: onStartTriage) {
                            Label {
                                Text("Start Triage", bundle: .module)
                            } icon: {
                                Image(systemName: "tray.full")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(theme.accent.color)
                        .accessibilityIdentifier("today.startTriage")
                    }
                    if let onAsk {
                        Button(action: onAsk) {
                            Label {
                                Text("Ask about my mail", bundle: .module)
                            } icon: {
                                Image(systemName: "sparkles")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(theme.accent.color)
                    }
                }
                .padding(.top, BrevSpacing.sm)
            }
        }
    }

    /// One sentence about the day, e.g. "3 conversations from people need
    /// you. 12 updates are unread."
    static func summary(_ digest: TodayDigest) -> String {
        let people = digest.waitingOnYouCount == 0
            ? String(localized: "Nothing from people needs you.", bundle: .module)
            : String(localized: "\(digest.waitingOnYouCount) conversations from people need you.", bundle: .module)
        guard digest.unreadUpdatesCount > 0 else { return people }
        return people + " "
            + String(localized: "\(digest.unreadUpdatesCount) updates are unread.", bundle: .module)
    }

    private func section(title: String, count: Int, rows: [TodayDigest.Row]) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.xs) {
            HStack(spacing: BrevSpacing.xs) {
                Text(verbatim: title)
                    .brevFont(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.textSecondary.color)
                Text(verbatim: "\(count)")
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ForEach(rows) { row in
                rowView(row)
            }
        }
    }

    private func rowView(_ row: TodayDigest.Row) -> some View {
        let person = row.person
        return Button {
            onOpen(row)
        } label: {
            HStack(spacing: BrevSpacing.md) {
                Text(verbatim: InitialsAvatar.initials(displayName: person.name, email: person.email))
                    .brevFont(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.textSecondary.color)
                    .frame(width: avatarSize, height: avatarSize)
                    .background(Circle().fill(theme.bgTertiary.color))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: person.name ?? person.email)
                        .brevFont(.body)
                        .fontWeight(row.header.isRead ? .regular : .semibold)
                        .foregroundStyle(theme.textPrimary.color)
                        .lineLimit(1)
                    Text(verbatim: row.header.subject)
                        .brevFont(.callout)
                        .foregroundStyle(theme.textSecondary.color)
                        .lineLimit(1)
                }
                Spacer(minLength: BrevSpacing.sm)
                Text(verbatim: Self.timeText(row.header.date, now: now, locale: locale))
                    .brevFont(.caption)
                    .foregroundStyle(theme.textTertiary.color)
                    .monospacedDigit()
            }
            .padding(.vertical, BrevSpacing.xs)
            .padding(.horizontal, BrevSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(TodayRowButtonStyle())
        .accessibilityValue(row.header.isRead ? "" : String(localized: "Unread", bundle: .module))
        .accessibilityHint(String(localized: "Opens the conversation", bundle: .module))
    }

    /// Time for today, day and month otherwise.
    static func timeText(_ date: Date, now: Date, locale: Locale, calendar: Calendar = .current) -> String {
        calendar.isDate(date, inSameDayAs: now)
            ? date.formatted(.dateTime.hour().minute().locale(locale))
            : date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }
}

/// A quiet hover/press fill for Today rows.
private struct TodayRowButtonStyle: ButtonStyle {
    @Environment(\.brevTheme) private var theme
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: BrevRadius.md)
                    .fill(theme.bgTertiary.color.opacity(configuration.isPressed ? 1 : isHovered ? 0.6 : 0))
            )
            .onHover { isHovered = $0 }
    }
}
