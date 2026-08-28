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

enum NotificationDeliveryExpectation {
    static let settingsCalloutMessage = String(
        localized: "While Brev is running, accounts use local sync, polling, IDLE, or provider history to alert you about new mail. When Brev is closed, alerts are limited to best-effort background refresh. Brev does not operate a push relay and does not promise closed-app delivery.",
        bundle: .module
    )

    static let quietHoursCalloutMessage = String(
        localized: "Quiet hours suppress local notifications on this device. Mail sync and background refresh continue while alerts are quiet.",
        bundle: .module
    )
}
