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

/// One source in the iOS compose paperclip menu. All sources are local:
/// nothing here talks to the network.
enum ComposeAttachMenuItem: String, Identifiable, Equatable, CaseIterable {
    case photoLibrary
    case camera
    case files
    case scanDocuments

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photoLibrary: return String(localized: "Photo Library", bundle: .module)
        case .camera: return String(localized: "Take Photo", bundle: .module)
        case .files: return String(localized: "Attach File", bundle: .module)
        case .scanDocuments: return String(localized: "Scan Documents", bundle: .module)
        }
    }

    var systemImage: String {
        switch self {
        case .photoLibrary: return "photo.on.rectangle"
        case .camera: return "camera"
        case .files: return "folder"
        case .scanDocuments: return "doc.viewfinder"
        }
    }
}

/// Decides which attachment sources the paperclip menu offers.
enum ComposeAttachMenuPolicy {
    /// Photos the Photos picker may return in one go.
    static let maxPhotoSelection = 10

    /// The menu items, in display order. Photo Library and Files are always
    /// present; Camera and Scan Documents only where the hardware allows.
    static func items(isCameraAvailable: Bool, isDocumentScanAvailable: Bool) -> [ComposeAttachMenuItem] {
        var items: [ComposeAttachMenuItem] = [.photoLibrary]
        if isCameraAvailable { items.append(.camera) }
        items.append(.files)
        if isDocumentScanAvailable { items.append(.scanDocuments) }
        return items
    }

    /// The filename given to a scanned document, e.g. "Scan 2026-10-09 10.13.pdf".
    static func scanFilename(date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return "Scan \(formatter.string(from: date)).pdf"
    }
}
