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

import BrevCalendar
import BrevDesign
import BrevThemes
import PhotosUI
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The contact editor sheet: create and edit for Google and CardDAV
/// contacts (ADR-0072 #9).
///
/// The view owns a ContactDraft it edits in place; saving goes through
/// ContactsEditingModel so capability checks, provider dispatch, and
/// conflict mapping stay out of the view. Google sources edit group
/// membership as toggles over discovered contact groups; CardDAV
/// sources edit CATEGORIES as free text. Photos upload from the
/// Photos picker — bytes land in draft.photoData and the write path
/// routes them per provider.
public struct ContactEditorView: View {
    @Environment(\.brevTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    /// The editing model that owns writable targets and mutations.
    let editing: ContactsEditingModel
    /// Called after a successful save so the browser reloads.
    let onSaved: () async -> Void

    @State private var draft: ContactDraft
    @State private var pickedPhotoItem: PhotosPickerItem?
    /// The source the edited/created contact belongs to — drives the
    /// provider-specific group section.
    private let source: PIMSource?

    /// Opens the editor for a new contact on a source.
    public init(
        editing: ContactsEditingModel,
        source: PIMSource?,
        onSaved: @escaping () async -> Void = {}
    ) {
        self.editing = editing
        self.source = source
        self.onSaved = onSaved
        _draft = State(initialValue: ContactDraft())
    }

    /// Opens the editor for an existing cached contact.
    public init(
        editing: ContactsEditingModel,
        contact: PIMContact,
        source: PIMSource?,
        onSaved: @escaping () async -> Void = {}
    ) {
        self.editing = editing
        self.source = source
        self.onSaved = onSaved
        _draft = State(initialValue: ContactDraft(contact: contact))
    }

    /// Opens the editor on a caller-built draft — for example an
    /// Add to Contacts pre-fill seeded from a message participant
    /// (#10). The draft must be a create draft (no provider identity);
    /// editing an existing contact still goes through the contact
    /// initializer.
    public init(
        editing: ContactsEditingModel,
        draft: ContactDraft,
        source: PIMSource?,
        onSaved: @escaping () async -> Void = {}
    ) {
        self.editing = editing
        self.source = source
        self.onSaved = onSaved
        _draft = State(initialValue: draft)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BrevSpacing.lg) {
                    photoSection
                    namesSection
                    organizationSection
                    targetSection
                    fieldsSection(
                        title: String(
                            localized: "Email",
                            bundle: .module
                        ),
                        symbol: "envelope",
                        placeholder: String(
                            localized: "name@example.com",
                            bundle: .module
                        ),
                        addTitle: String(
                            localized: "Add email",
                            bundle: .module
                        ),
                        fields: $draft.emails
                    )
                    fieldsSection(
                        title: String(
                            localized: "Phone",
                            bundle: .module
                        ),
                        symbol: "phone",
                        placeholder: String(
                            localized: "+47 000 00 000",
                            bundle: .module
                        ),
                        addTitle: String(
                            localized: "Add phone",
                            bundle: .module
                        ),
                        fields: $draft.phones
                    )
                    fieldsSection(
                        title: String(
                            localized: "URLs",
                            bundle: .module
                        ),
                        symbol: "link",
                        placeholder: String(
                            localized: "https://example.com",
                            bundle: .module
                        ),
                        addTitle: String(
                            localized: "Add URL",
                            bundle: .module
                        ),
                        fields: $draft.urls
                    )
                    datesSection
                    addressesSection
                    groupsSection
                    notesSection
                    if let lastError = editing.lastError {
                        Text(lastError)
                            .brevFont(.caption)
                            .foregroundStyle(theme.danger.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(BrevSpacing.lg)
            }
            .background(theme.bgPrimary.color)
            .navigationTitle(
                draft.isEditing
                    ? String(localized: "Edit Contact", bundle: .module)
                    : String(localized: "New Contact", bundle: .module)
            )
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
        .onAppear {
            if draft.targetID == nil {
                draft.targetID = editing.defaultTarget?.id
            }
        }
        .onChange(of: pickedPhotoItem) { _, item in
            if let item { Task { await applyPickedPhoto(item) } }
        }
    }

    // MARK: - Sections

    /// The photo row: current photo preview plus pick/remove actions.
    /// Preview shows only bytes Brev holds — a provider-hosted photoURL
    /// is never fetched (ADR-0006), so it renders as the placeholder.
    private var photoSection: some View {
        HStack(spacing: BrevSpacing.md) {
            photoPreview
                .frame(width: 56, height: 56)
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(
                        theme.textSecondary.color.opacity(0.3)
                    )
                )
            VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                PhotosPicker(
                    selection: $pickedPhotoItem,
                    matching: .images
                ) {
                    Text(
                        hasPhoto
                            ? String(
                                localized: "Change Photo",
                                bundle: .module
                            )
                            : String(
                                localized: "Choose Photo",
                                bundle: .module
                            )
                    )
                }
                .brevFont(.body)
                if hasPhoto {
                    Button(
                        String(
                            localized: "Remove Photo",
                            bundle: .module
                        ),
                        role: .destructive
                    ) {
                        draft.photoRemoved = true
                        draft.photoData = nil
                        draft.photoURL = nil
                    }
                    .brevFont(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.danger.color)
                }
            }
        }
    }

    @ViewBuilder
    private var photoPreview: some View {
        if !draft.photoRemoved,
           let data = draft.photoData,
           let image = platformImage(data) {
            image.resizable().scaledToFill()
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(theme.textSecondary.color)
        }
    }

    private var hasPhoto: Bool {
        !draft.photoRemoved
            && (draft.photoData != nil || draft.photoURL != nil)
    }

    /// Stores the picked image: JPEG when the bytes decode (so a HEIC
    /// pick uploads in a format both providers accept), else the raw
    /// data — the writers emit whatever arrives.
    @MainActor
    private func applyPickedPhoto(_ item: PhotosPickerItem) async {
        defer { pickedPhotoItem = nil }
        guard let data = try? await item.loadTransferable(
            type: Data.self
        ) else { return }
        draft.photoData = Self.jpegData(for: data) ?? data
        draft.photoRemoved = false
    }

    private func platformImage(_ data: Data) -> Image? {
        #if os(macOS)
        NSImage(data: data).map { Image(nsImage: $0) }
        #else
        UIImage(data: data).map { Image(uiImage: $0) }
        #endif
    }

    /// Re-encodes to JPEG so picked HEIC/WEBP bytes reach providers in
    /// a supported format; nil when the data is not a decodable image.
    private static func jpegData(for data: Data) -> Data? {
        #if os(macOS)
        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }
        return bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.85]
        )
        #else
        return UIImage(data: data)?.jpegData(compressionQuality: 0.85)
        #endif
    }

    /// A labeled editable-date list: each row is a label field, a date
    /// picker, an "include year" toggle, and a remove button.
    private var datesSection: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            Label(
                String(localized: "Dates", bundle: .module),
                systemImage: "calendar"
            )
            .brevFont(.subheadline)
            .foregroundStyle(theme.textSecondary.color)
            ForEach(
                Array($draft.dates.enumerated()),
                id: \.offset
            ) { index, _ in
                HStack(spacing: BrevSpacing.sm) {
                    TextField(
                        String(localized: "Label", bundle: .module),
                        text: dateLabelBinding(at: index)
                    )
                    .frame(width: 72)
                    .brevFont(.caption)
                    DatePicker(
                        "",
                        selection: dateBinding(at: index),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    Toggle(
                        String(localized: "Year", bundle: .module),
                        isOn: yearBinding(at: index)
                    )
                    .brevFont(.caption)
                    Button {
                        draft.dates.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(theme.danger.color)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                draft.dates.append(
                    PIMContactDate(
                        label: "birthday",
                        year: nil,
                        month: Calendar.current.component(
                            .month,
                            from: Date()
                        ),
                        day: Calendar.current.component(
                            .day,
                            from: Date()
                        )
                    )
                )
            } label: {
                Label(
                    String(localized: "Add date", bundle: .module),
                    systemImage: "plus.circle"
                )
                .brevFont(.body)
                .foregroundStyle(theme.accent.color)
            }
            .buttonStyle(.plain)
        }
    }

    private func dateLabelBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { draft.dates[safe: index]?.label ?? "" },
            set: { newValue in
                guard index < draft.dates.count else { return }
                draft.dates[index].label =
                    newValue.isEmpty ? nil : newValue
            }
        )
    }

    private func dateBinding(at index: Int) -> Binding<Date> {
        Binding(
            get: { draft.dates[safe: index]?.date ?? Date() },
            set: { newValue in
                guard index < draft.dates.count else { return }
                draft.dates[index] =
                    draft.dates[index].withDate(newValue)
            }
        )
    }

    private func yearBinding(at index: Int) -> Binding<Bool> {
        Binding(
            get: { draft.dates[safe: index]?.year != nil },
            set: { hasYear in
                guard index < draft.dates.count else { return }
                draft.dates[index].year = hasYear
                    ? Calendar.current.component(.year, from: Date())
                    : nil
            }
        )
    }

    private var namesSection: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            TextField(
                String(localized: "First name", bundle: .module),
                text: $draft.givenName
            )
            .textFieldStyle(.plain)
            .brevFont(.title)
            .foregroundStyle(theme.textPrimary.color)
            TextField(
                String(localized: "Last name", bundle: .module),
                text: $draft.familyName
            )
            .textFieldStyle(.plain)
            .brevFont(.title)
            .foregroundStyle(theme.textPrimary.color)
            LabeledContent(
                String(localized: "Nickname", bundle: .module)
            ) {
                TextField(
                    String(localized: "Optional", bundle: .module),
                    text: $draft.nickname
                )
                .multilineTextAlignment(.trailing)
            }
        }
    }

    private var organizationSection: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            LabeledContent(
                String(localized: "Organization", bundle: .module)
            ) {
                TextField(
                    String(localized: "Company", bundle: .module),
                    text: $draft.organization
                )
                .multilineTextAlignment(.trailing)
            }
            LabeledContent(
                String(localized: "Job title", bundle: .module)
            ) {
                TextField(
                    String(localized: "Role", bundle: .module),
                    text: $draft.jobTitle
                )
                .multilineTextAlignment(.trailing)
            }
        }
    }

    /// A labeled multi-value section (emails or phones): each row is a
    /// label field plus a value field plus a remove button, with an
    /// add affordance under the list.
    private func fieldsSection(
        title: String,
        symbol: String,
        placeholder: String,
        addTitle: String,
        fields: Binding<[PIMContactField]>
    ) -> some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            Label(title, systemImage: symbol)
                .brevFont(.subheadline)
                .foregroundStyle(theme.textSecondary.color)
            ForEach(
                Array(fields.wrappedValue.enumerated()),
                id: \.offset
            ) { index, _ in
                HStack(spacing: BrevSpacing.sm) {
                    TextField(
                        String(localized: "Label", bundle: .module),
                        text: labelBinding(for: fields, at: index)
                    )
                    .frame(width: 72)
                    .brevFont(.caption)
                    TextField(placeholder, text: valueBinding(
                        for: fields,
                        at: index
                    ))
                    #if os(iOS)
                    .autocapitalization(.none)
                    #endif
                    .disableAutocorrection(true)
                    Button {
                        fields.wrappedValue.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(theme.danger.color)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                fields.wrappedValue.append(
                    PIMContactField(label: nil, value: "")
                )
            } label: {
                Label(addTitle, systemImage: "plus.circle")
                    .brevFont(.body)
                    .foregroundStyle(theme.accent.color)
            }
            .buttonStyle(.plain)
        }
    }

    /// The address-book picker — explicit target selection for new
    /// contacts and moves between CardDAV books. Google has a single
    /// account-wide target, so the picker hides there; group
    /// membership is edited below instead.
    @ViewBuilder
    private var targetSection: some View {
        if editing.targets.count > 1 {
            Picker(
                String(localized: "Address book", bundle: .module),
                selection: $draft.targetID
            ) {
                ForEach(editing.targets) { target in
                    Text(target.title)
                        .tag(Optional(target.id))
                }
            }
        }
    }

    /// Bindings into an indexed element — the enumerated offset is the
    /// row identity, matching the detail view's convention.
    private func labelBinding(
        for fields: Binding<[PIMContactField]>,
        at index: Int
    ) -> Binding<String> {
        Binding(
            get: { fields.wrappedValue[safe: index]?.label ?? "" },
            set: { newValue in
                guard index < fields.wrappedValue.count else { return }
                fields.wrappedValue[index].label =
                    newValue.isEmpty ? nil : newValue
            }
        )
    }

    private func valueBinding(
        for fields: Binding<[PIMContactField]>,
        at index: Int
    ) -> Binding<String> {
        Binding(
            get: { fields.wrappedValue[safe: index]?.value ?? "" },
            set: { newValue in
                guard index < fields.wrappedValue.count else { return }
                fields.wrappedValue[index].value = newValue
            }
        )
    }

    private var addressesSection: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            Label(
                String(localized: "Addresses", bundle: .module),
                systemImage: "mappin"
            )
            .brevFont(.subheadline)
            .foregroundStyle(theme.textSecondary.color)
            ForEach(
                Array($draft.addresses.enumerated()),
                id: \.offset
            ) { index, _ in
                VStack(alignment: .leading, spacing: BrevSpacing.xxs) {
                    HStack(spacing: BrevSpacing.sm) {
                        TextField(
                            String(localized: "Label", bundle: .module),
                            text: addressLabelBinding(at: index)
                        )
                        .frame(width: 72)
                        .brevFont(.caption)
                        Spacer()
                        Button {
                            draft.addresses.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(theme.danger.color)
                        }
                        .buttonStyle(.plain)
                    }
                    TextField(
                        String(localized: "Street", bundle: .module),
                        text: addressBinding(at: index, \.street)
                    )
                    HStack(spacing: BrevSpacing.sm) {
                        TextField(
                            String(localized: "City", bundle: .module),
                            text: addressBinding(at: index, \.city)
                        )
                        TextField(
                            String(
                                localized: "Postal code",
                                bundle: .module
                            ),
                            text: addressBinding(at: index, \.postalCode)
                        )
                        .frame(maxWidth: 110)
                    }
                    HStack(spacing: BrevSpacing.sm) {
                        TextField(
                            String(localized: "Region", bundle: .module),
                            text: addressBinding(at: index, \.region)
                        )
                        TextField(
                            String(localized: "Country", bundle: .module),
                            text: addressBinding(at: index, \.country)
                        )
                    }
                }
                .padding(BrevSpacing.sm)
                .background(theme.bgSecondary.color)
                .clipShape(
                    RoundedRectangle(cornerRadius: BrevRadius.sm)
                )
            }
            Button {
                draft.addresses.append(PIMContactAddress())
            } label: {
                Label(
                    String(localized: "Add address", bundle: .module),
                    systemImage: "plus.circle"
                )
                .brevFont(.body)
                .foregroundStyle(theme.accent.color)
            }
            .buttonStyle(.plain)
        }
    }

    private func addressLabelBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { draft.addresses[safe: index]?.label ?? "" },
            set: { newValue in
                guard index < draft.addresses.count else { return }
                draft.addresses[index].label =
                    newValue.isEmpty ? nil : newValue
            }
        )
    }

    private func addressBinding(
        at index: Int,
        _ keyPath: WritableKeyPath<PIMContactAddress, String?>
    ) -> Binding<String> {
        Binding(
            get: { draft.addresses[safe: index]?[keyPath: keyPath] ?? "" },
            set: { newValue in
                guard index < draft.addresses.count else { return }
                draft.addresses[index][keyPath: keyPath] =
                    newValue.isEmpty ? nil : newValue
            }
        )
    }

    /// Group membership editing — Google contact groups as toggles,
    /// CardDAV categories as comma-separated text. Hidden when the
    /// source exposes no editable groups.
    @ViewBuilder
    private var groupsSection: some View {
        if let source, source.provider == .google {
            let groups = editing.editableGroups(for: source.id)
            if !groups.isEmpty {
                VStack(alignment: .leading, spacing: BrevSpacing.sm) {
                    Label(
                        String(localized: "Groups", bundle: .module),
                        systemImage: "person.3"
                    )
                    .brevFont(.subheadline)
                    .foregroundStyle(theme.textSecondary.color)
                    ForEach(groups) { group in
                        Toggle(
                            group.displayName,
                            isOn: groupBinding(group.providerKey)
                        )
                        .toggleStyle(.switch)
                    }
                }
            }
        } else if let source, source.provider == .cardDAV {
            LabeledContent(
                String(localized: "Groups", bundle: .module)
            ) {
                TextField(
                    String(
                        localized: "Comma-separated",
                        bundle: .module
                    ),
                    text: categoriesBinding
                )
                .multilineTextAlignment(.trailing)
            }
        }
    }

    private func groupBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { draft.groupKeys.contains(key) },
            set: { isOn in
                if isOn, !draft.groupKeys.contains(key) {
                    draft.groupKeys.append(key)
                } else if !isOn {
                    draft.groupKeys.removeAll { $0 == key }
                }
            }
        )
    }

    /// CardDAV groupKeys are CATEGORIES strings — edited as one
    /// comma-separated field.
    private var categoriesBinding: Binding<String> {
        Binding(
            get: { draft.groupKeys.joined(separator: ", ") },
            set: { newValue in
                draft.groupKeys = newValue
                    .split(separator: ",")
                    .map {
                        $0.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                    }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: BrevSpacing.sm) {
            Label(
                String(localized: "Notes", bundle: .module),
                systemImage: "text.alignleft"
            )
            .brevFont(.subheadline)
            .foregroundStyle(theme.textSecondary.color)
            TextEditor(text: $draft.note)
                .brevFont(.body)
                .foregroundStyle(theme.textPrimary.color)
                .frame(minHeight: 96)
                .scrollContentBackground(.hidden)
                .background(theme.bgSecondary.color)
                .clipShape(
                    RoundedRectangle(cornerRadius: BrevRadius.sm)
                )
        }
    }

    // MARK: - Toolbar + actions

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(String(localized: "Cancel", bundle: .module)) {
                dismiss()
            }
            .disabled(editing.isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(
                draft.isEditing
                    ? String(localized: "Save", bundle: .module)
                    : String(localized: "Add", bundle: .module)
            ) {
                Task { await commitSave() }
            }
            .disabled(!draft.isValid || editing.isSaving)
        }
    }

    private func commitSave() async {
        do {
            _ = try await editing.save(draft)
            await onSaved()
            dismiss()
        } catch {
            // The model already surfaced the error text inline.
        }
    }
}

private extension Array {
    /// Safe subscript for indexed editor rows — a stale index reads
    /// nil instead of trapping.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
