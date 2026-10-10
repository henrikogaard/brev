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

#if os(iOS)
import SwiftUI
import UIKit

/// Reports a swipe-down that `interactiveDismissDisabled` refused.
///
/// SwiftUI blocks the swipe but has no callback for it. UIKit does:
/// `presentationControllerDidAttemptToDismiss`. SwiftUI owns the sheet's
/// presentation-controller delegate, so this installs a forwarding proxy in
/// front of it: every delegate message still reaches SwiftUI's delegate, and
/// the attempt callback is added on top.
struct ComposeDismissAttemptObserver: UIViewControllerRepresentable {
    let onAttempt: () -> Void

    func makeUIViewController(context: Context) -> ObserverController {
        let controller = ObserverController()
        controller.onAttempt = onAttempt
        return controller
    }

    func updateUIViewController(_ controller: ObserverController, context: Context) {
        controller.onAttempt = onAttempt
        // SwiftUI may reinstall its own delegate when the sheet's dismissal
        // flag changes; put the proxy back in front of it.
        DispatchQueue.main.async { [weak controller] in
            controller?.installProxyIfNeeded()
        }
    }

    final class ObserverController: UIViewController {
        var onAttempt: (() -> Void)?
        private var proxy: DelegateProxy?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.isHidden = true
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            installProxyIfNeeded()
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            DispatchQueue.main.async { [weak self] in
                self?.installProxyIfNeeded()
            }
        }

        func installProxyIfNeeded() {
            // The presented sheet is the root of this controller's parent chain.
            // Asking a child controller for `presentationController` would
            // fabricate an unrelated one, so go to the root first.
            var root: UIViewController = self
            while let parent = root.parent {
                root = parent
            }
            guard root.presentingViewController != nil,
                  let presentation = root.presentationController else { return }
            if let proxy, presentation.delegate === proxy { return }
            let proxy = DelegateProxy(original: presentation.delegate) { [weak self] in
                self?.onAttempt?()
            }
            self.proxy = proxy
            presentation.delegate = proxy
        }
    }

    /// Forwards everything to the delegate SwiftUI installed and adds the
    /// "attempted to dismiss" callback.
    final class DelegateProxy: NSObject, UIAdaptivePresentationControllerDelegate {
        private weak var original: UIAdaptivePresentationControllerDelegate?
        private let onAttempt: () -> Void

        init(original: UIAdaptivePresentationControllerDelegate?, onAttempt: @escaping () -> Void) {
            self.original = original
            self.onAttempt = onAttempt
        }

        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            onAttempt()
            original?.presentationControllerDidAttemptToDismiss?(presentationController)
        }

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (original as AnyObject?)?.responds(to: selector) == true
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            if let original, (original as AnyObject).responds(to: selector) {
                return original
            }
            return super.forwardingTarget(for: selector)
        }
    }
}
#endif
