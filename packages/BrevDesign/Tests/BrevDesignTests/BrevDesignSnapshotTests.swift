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

#if canImport(UIKit)
import BrevDesign
import BrevThemes
import SnapshotTesting
import SwiftUI
import Testing

/// Snapshot coverage for the core design primitives, rendered once
/// per built-in theme. Snapshots are committed under
/// `__Snapshots__/` alongside the test file. To re-record, set
/// `SNAPSHOT_TESTING_RECORD=true` in the environment before running
/// `xcodebuild test` (see `README.md` §Snapshot tests).
@Suite("BrevDesign snapshots")
struct BrevDesignSnapshotTests {
    @Test("BrevButton renders in every built-in theme", arguments: BrevTheme.brevBuiltIns)
    @MainActor
    func brevButtonRendersInTheme(_ theme: BrevTheme) throws {
        let view = VStack(spacing: 12) {
            BrevButton("Send", style: .primary) {}
            BrevButton("Cancel", style: .secondary) {}
            BrevButton("More", style: .tertiary) {}
            BrevButton("Delete", style: .destructive) {}
        }
        .padding(16)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .frame(width: 220)

        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear

        assertSnapshot(
            of: host,
            as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
            named: theme.id
        )
    }

    @Test("BrevInlineStatus renders in every built-in theme", arguments: BrevTheme.brevBuiltIns)
    @MainActor
    func brevInlineStatusRendersInTheme(_ theme: BrevTheme) throws {
        let view = VStack(spacing: 12) {
            BrevInlineStatus(
                message: "Folder refresh failed. Check your connection and try again.",
                tone: .danger,
                actionTitle: "Retry",
                onAction: {},
                onDismiss: {}
            )
            BrevInlineStatus(
                message: "Mailbox is up to date.",
                tone: .success
            )
        }
        .padding(16)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .frame(width: 340)

        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear

        assertSnapshot(
            of: host,
            as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
            named: theme.id
        )
    }

    @Test("BrevSkeleton renders in every built-in theme", arguments: BrevTheme.brevBuiltIns)
    @MainActor
    func brevSkeletonRendersInTheme(_ theme: BrevTheme) throws {
        let view = VStack(spacing: 16) {
            BrevSkeletonList(rowCount: 3)
            BrevSkeletonText(lineCount: 4)
        }
        .padding(16)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .frame(width: 340)

        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear

        assertSnapshot(
            of: host,
            as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
            named: theme.id
        )
    }

    @Test("Brev surface primitives render in every built-in theme", arguments: BrevTheme.brevBuiltIns)
    @MainActor
    func brevSurfacePrimitivesRenderInTheme(_ theme: BrevTheme) throws {
        let view = VStack(alignment: .leading, spacing: 12) {
            BrevCard {
                Text("Privacy")
                    .brevFont(.headline)
                    .foregroundStyle(theme.textPrimary.color)
                Text("External avatar lookups stay off until you choose them.")
                    .brevFont(.footnote)
                    .foregroundStyle(theme.textSecondary.color)
            }

            BrevCard(style: .selected) {
                Text("Selected mailbox")
                    .brevFont(.headline)
                    .foregroundStyle(theme.textPrimary.color)
                Text("alex@example.test")
                    .brevFont(.footnote)
                    .foregroundStyle(theme.textSecondary.color)
            }

            BrevToast(
                message: "Message archived.",
                tone: .success,
                actionTitle: "Undo",
                onAction: {},
                onDismiss: {}
            )
        }
        .padding(16)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .frame(width: 340)

        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear

        assertSnapshot(
            of: host,
            as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
            named: theme.id
        )
    }

    @Test("Brev remaining components render in every built-in theme", arguments: BrevTheme.brevBuiltIns)
    @MainActor
    func brevRemainingComponentsRenderInTheme(_ theme: BrevTheme) throws {
        let view = VStack(alignment: .leading, spacing: 12) {
            BrevDivider()

            BrevListRow(
                title: "Inbox",
                subtitle: "12 unread messages",
                leading: { Image(systemName: "tray").frame(width: 20) },
                trailing: { Image(systemName: "chevron.right").foregroundStyle(theme.textTertiary.color) }
            )

            BrevListRow(
                title: "Selected item",
                subtitle: "Active conversation",
                isSelected: true,
                // `leading` is not the last parameter (`trailing` follows), so a
                // trailing closure would bind to the wrong slot — keep the label.
                // swiftlint:disable:next trailing_closure
                leading: { Image(systemName: "envelope.fill").frame(width: 20) }
            )

            BrevProgressSurface(label: "Loading messages")

            BrevStatusBanner(
                style: .info,
                title: "Sync paused",
                message: "Check your connection."
            )

            BrevStatusBanner(
                style: .warning,
                title: "Storage almost full",
                action: (label: "Manage", handler: {})
            )
        }
        .padding(16)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .frame(width: 340)

        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear

        assertSnapshot(
            of: host,
            as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
            named: theme.id
        )
    }

    @Test("BrevToast renders all tones in every built-in theme", arguments: BrevTheme.brevBuiltIns)
    @MainActor
    func brevToastTonesRenderInTheme(_ theme: BrevTheme) throws {
        let view = VStack(spacing: 8) {
            BrevToast(
                message: "Info notification.",
                tone: .info
            )
            BrevToast(
                message: "Operation completed successfully.",
                tone: .success,
                actionTitle: "Undo",
                // `onAction` precedes `onDismiss`, so a trailing closure binds wrong.
                // swiftlint:disable:next trailing_closure
                onAction: {}
            )
            BrevToast(
                message: "Something needs attention.",
                tone: .warning,
                actionTitle: "View",
                // `onAction` precedes `onDismiss`, so a trailing closure binds wrong.
                // swiftlint:disable:next trailing_closure
                onAction: {}
            )
            BrevToast(
                message: "An error occurred.",
                tone: .danger,
                actionTitle: "Retry",
                // `onAction` precedes `onDismiss`, so a trailing closure binds wrong.
                // swiftlint:disable:next trailing_closure
                onAction: {}
            )
        }
        .padding(16)
        .background(theme.bgPrimary.color)
        .brevTheme(theme)
        .frame(width: 340)

        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear

        assertSnapshot(
            of: host,
            as: .image(on: .iPhone13Pro, traits: .init(displayScale: 2)),
            named: theme.id
        )
    }
}
#endif
