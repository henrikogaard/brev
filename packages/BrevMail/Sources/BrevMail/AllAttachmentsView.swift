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

import BrevBackend
import BrevDesign
import BrevThemes
import SwiftUI

/// The All Attachments surface: a flat, filterable list of every cached
/// attachment across the mailbox. Records are supplied read-only by an
/// `AttachmentSearchRecordProviding`; tapping a row routes to the owning
/// message via `onOpen`.
struct AllAttachmentsView: View {
    @Environment(\.brevTheme) private var theme
    let provider: any AttachmentSearchRecordProviding
    @Bindable var navigation: MailNavigationState
    let onOpen: (AttachmentSearchRoute) -> Void

    @State private var records: [AttachmentSearchRecord] = []
    @State private var filter = AttachmentSearchFilter.allAttachments
    /// The filter `rows` is actually derived from. It lags `filter` by a short
    /// debounce so the filter+sort over every cached attachment runs at most a
    /// few times a second while typing, not on every keystroke.
    @State private var appliedFilter = AttachmentSearchFilter.allAttachments
    @State private var isLoaded = false

    init(
        provider: any AttachmentSearchRecordProviding,
        navigation: MailNavigationState,
        initialFilter: AttachmentSearchFilter = .allAttachments,
        onOpen: @escaping (AttachmentSearchRoute) -> Void
    ) {
        self.provider = provider
        _navigation = Bindable(wrappedValue: navigation)
        self.onOpen = onOpen
        _filter = State(initialValue: initialFilter)
        _appliedFilter = State(initialValue: initialFilter)
    }

    /// Seeds records and filter synchronously, for SwiftUI previews and
    /// snapshot tests where the asynchronous `.task` load would not complete
    /// before the view is rendered.
    init(
        previewRecords: [AttachmentSearchRecord],
        navigation: MailNavigationState,
        filter: AttachmentSearchFilter = .allAttachments,
        onOpen: @escaping (AttachmentSearchRoute) -> Void
    ) {
        provider = StubAttachmentSearchRecordProvider(records: previewRecords)
        _navigation = Bindable(wrappedValue: navigation)
        self.onOpen = onOpen
        _records = State(initialValue: previewRecords)
        _filter = State(initialValue: filter)
        _appliedFilter = State(initialValue: filter)
        _isLoaded = State(initialValue: true)
    }

    private var rows: [AttachmentSearchRow] {
        AttachmentSearchPresentation.rows(records: records, filter: appliedFilter)
    }

    var body: some View {
        VStack(spacing: 0) {
            AttachmentSearchFilterBar(filter: $filter)
            if rows.isEmpty {
                emptyState
            } else {
                List(rows) { row in
                    AttachmentSearchRowView(row: row)
                        .contentShape(Rectangle())
                        .onTapGesture { onOpen(row.route) }
                }
                .listStyle(.plain)
            }
        }
        .background(theme.bgPrimary.color)
        .task {
            guard !isLoaded else { return }
            records = await provider.attachmentRecords()
            isLoaded = true
        }
        .task(id: filter) {
            // Debounce live filter edits before the (potentially large)
            // filter+sort runs. Seeded equal, so the first pass is immediate.
            guard appliedFilter != filter else { return }
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            appliedFilter = filter
        }
    }

    private var emptyState: some View {
        VStack(spacing: BrevSpacing.md) {
            Image(systemName: "paperclip")
                .font(.system(size: 36))
                .foregroundStyle(theme.textSecondary.color)
            Text("No attachments", bundle: .module)
                .brevFont(.headline)
                .foregroundStyle(theme.textPrimary.color)
            Text("Attachments from your cached messages will appear here.", bundle: .module)
                .brevFont(.subheadline)
                .foregroundStyle(theme.textSecondary.color)
                .multilineTextAlignment(.center)
        }
        .padding(BrevSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Query + file-type filter controls for the All Attachments surface.
struct AttachmentSearchFilterBar: View {
    @Environment(\.brevTheme) private var theme
    @Binding var filter: AttachmentSearchFilter

    var body: some View {
        HStack(spacing: BrevSpacing.sm) {
            HStack(spacing: BrevSpacing.xs) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(theme.textSecondary.color)
                TextField(String(localized: "Search attachments", bundle: .module), text: $filter.query)
                    .textFieldStyle(.plain)
                    .brevFont(.body)
                    .foregroundStyle(theme.textPrimary.color)
            }
            .padding(.horizontal, BrevSpacing.sm)
            .padding(.vertical, BrevSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: BrevRadius.sm)
                    .fill(theme.bgSecondary.color)
            )

            Menu {
                Picker(String(localized: "File type", bundle: .module), selection: $filter.fileType) {
                    Text("All", bundle: .module).tag(AttachmentSearchFileType?.none)
                    Text("PDF", bundle: .module).tag(AttachmentSearchFileType?.some(.pdf))
                    Text("Images", bundle: .module).tag(AttachmentSearchFileType?.some(.image))
                    Text("Documents", bundle: .module).tag(AttachmentSearchFileType?.some(.document))
                    Text("Spreadsheets", bundle: .module).tag(AttachmentSearchFileType?.some(.spreadsheet))
                    Text("Archives", bundle: .module).tag(AttachmentSearchFileType?.some(.archive))
                    Text("Other", bundle: .module).tag(AttachmentSearchFileType?.some(.other))
                }
            } label: {
                HStack(spacing: BrevSpacing.xs) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text(Self.label(for: filter.fileType))
                        .brevFont(.subheadline)
                }
                .foregroundStyle(theme.accent.color)
            }
        }
        .padding(.horizontal, BrevSpacing.lg)
        .padding(.vertical, BrevSpacing.sm)
    }

    private static func label(for fileType: AttachmentSearchFileType?) -> String {
        switch fileType {
        case .none: return "All"
        case .pdf: return "PDF"
        case .image: return "Images"
        case .document: return "Documents"
        case .spreadsheet: return "Spreadsheets"
        case .archive: return "Archives"
        case .other: return "Other"
        }
    }
}

/// A single attachment row: glyph, filename, context line, and an optional
/// degraded-state badge when the attachment must be downloaded or isn't
/// content-indexed.
struct AttachmentSearchRowView: View {
    @Environment(\.brevTheme) private var theme
    let row: AttachmentSearchRow

    private var contextLine: String {
        [row.subject, row.sender, row.folderName]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var degradedMessage: String? {
        if let first = row.degradedStateMessages.first {
            return first
        }
        if row.availability == .downloadRequired {
            return "Download required"
        }
        return nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: BrevSpacing.md) {
            Image(systemName: "paperclip")
                .foregroundStyle(theme.textSecondary.color)
                .padding(.top, BrevSpacing.xxs)

            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                Text(row.filename)
                    .brevFont(.headline)
                    .foregroundStyle(theme.textPrimary.color)

                if !contextLine.isEmpty {
                    Text(contextLine)
                        .brevFont(.subheadline)
                        .foregroundStyle(theme.textSecondary.color)
                }

                if let degradedMessage {
                    Text(degradedMessage)
                        .brevFont(.caption)
                        .foregroundStyle(theme.accent.color)
                        .padding(.horizontal, BrevSpacing.sm)
                        .padding(.vertical, BrevSpacing.xxs)
                        .background(
                            RoundedRectangle(cornerRadius: BrevRadius.sm)
                                .fill(theme.accentMuted.color)
                        )
                }
            }
        }
        .padding(.vertical, BrevSpacing.xs)
    }
}
