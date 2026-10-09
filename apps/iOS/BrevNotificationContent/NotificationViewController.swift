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

import UIKit
import UserNotifications
import UserNotificationsUI

final class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private let avatarView = UIView()
    private let avatarLabel = UILabel()
    private let senderLabel = UILabel()
    private let subjectLabel = UILabel()
    private let snippetLabel = UILabel()
    private let dateLabel = UILabel()
    private let separatorView = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    func didReceive(_ notification: UNNotification) {
        let content = notification.request.content
        configure(with: content, fallbackDate: notification.date)
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        // Neutral system fill: the extension is dependency-free (no BrevThemes), and a
        // hard-coded accent hue would ignore the user's theme and appearance.
        avatarView.backgroundColor = .systemGray5
        avatarView.layer.cornerRadius = 20
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(avatarView)

        avatarLabel.font = Self.scaledFont(.headline, weight: .semibold, maximumPointSize: 24)
        avatarLabel.adjustsFontForContentSizeCategory = true
        avatarLabel.textColor = .label
        avatarLabel.textAlignment = .center
        avatarLabel.translatesAutoresizingMaskIntoConstraints = false
        avatarView.addSubview(avatarLabel)

        senderLabel.font = Self.scaledFont(.subheadline, weight: .semibold)
        senderLabel.adjustsFontForContentSizeCategory = true
        senderLabel.textColor = .label
        senderLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(senderLabel)

        dateLabel.font = Self.scaledFont(.caption1)
        dateLabel.adjustsFontForContentSizeCategory = true
        dateLabel.textColor = .secondaryLabel
        dateLabel.textAlignment = .right
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dateLabel)

        subjectLabel.font = Self.scaledFont(.subheadline, weight: .medium)
        subjectLabel.adjustsFontForContentSizeCategory = true
        subjectLabel.textColor = .label
        subjectLabel.numberOfLines = 2
        subjectLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subjectLabel)

        snippetLabel.font = Self.scaledFont(.footnote)
        snippetLabel.adjustsFontForContentSizeCategory = true
        snippetLabel.textColor = .secondaryLabel
        snippetLabel.numberOfLines = 3
        snippetLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(snippetLabel)

        separatorView.backgroundColor = .separator
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(separatorView)

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            avatarView.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            avatarView.widthAnchor.constraint(equalToConstant: 40),
            avatarView.heightAnchor.constraint(equalToConstant: 40),

            avatarLabel.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            avatarLabel.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),

            senderLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            senderLabel.topAnchor.constraint(equalTo: avatarView.topAnchor),
            senderLabel.trailingAnchor.constraint(lessThanOrEqualTo: dateLabel.leadingAnchor, constant: -8),

            dateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            dateLabel.topAnchor.constraint(equalTo: senderLabel.topAnchor),
            dateLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 80),

            subjectLabel.leadingAnchor.constraint(equalTo: senderLabel.leadingAnchor),
            subjectLabel.topAnchor.constraint(equalTo: senderLabel.bottomAnchor, constant: 4),
            subjectLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            separatorView.leadingAnchor.constraint(equalTo: subjectLabel.leadingAnchor),
            separatorView.topAnchor.constraint(equalTo: subjectLabel.bottomAnchor, constant: 8),
            separatorView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            separatorView.heightAnchor.constraint(equalToConstant: 0.5),

            snippetLabel.leadingAnchor.constraint(equalTo: separatorView.leadingAnchor),
            snippetLabel.topAnchor.constraint(equalTo: separatorView.bottomAnchor, constant: 8),
            snippetLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            snippetLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)
        ])
    }

    private func configure(with content: UNNotificationContent, fallbackDate: Date) {
        let sender = content.userInfo["senderName"] as? String
            ?? content.title
        let subject = content.userInfo["subject"] as? String
            ?? content.subtitle
        let snippet = content.userInfo["snippet"] as? String
            ?? content.body
        let dateString = content.userInfo["date"] as? String

        senderLabel.text = sender
        subjectLabel.text = subject
        snippetLabel.text = snippet
        dateLabel.text = relativeDate(from: dateString, fallbackDate: fallbackDate)

        let initials = senderInitials(from: sender)
        avatarLabel.text = initials
    }

    private func senderInitials(from name: String) -> String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private func relativeDate(from dateString: String?, fallbackDate: Date) -> String {
        let date = dateString.flatMap(Self.iso8601Formatter.date(from:))
            ?? fallbackDate
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private static let iso8601Formatter = ISO8601DateFormatter()

    /// A system font that follows Dynamic Type for `style`.
    private static func scaledFont(
        _ style: UIFont.TextStyle,
        weight: UIFont.Weight = .regular,
        maximumPointSize: CGFloat? = nil
    ) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        let font = UIFont.systemFont(ofSize: base.pointSize, weight: weight)
        let metrics = UIFontMetrics(forTextStyle: style)
        if let maximumPointSize {
            return metrics.scaledFont(for: font, maximumPointSize: maximumPointSize)
        }
        return metrics.scaledFont(for: font)
    }
}
