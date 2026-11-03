#if os(macOS)
import AppKit
#else
import SafariServices
import UIKit
#endif

enum ExternalLinkOpener {
    /// Shows the page in an in-app Safari sheet on iOS, and in the default browser on macOS.
    @MainActor
    static func open(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        guard let presenter = topmostViewController() else { return }
        let safari = SFSafariViewController(url: url)
        safari.modalPresentationStyle = .pageSheet
        presenter.present(safari, animated: true)
        #endif
    }

    #if os(iOS)
    @MainActor
    private static func topmostViewController() -> UIViewController? {
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
            let root = windowScene.keyWindow?.rootViewController
        else { return nil }
        return topmost(from: root)
    }

    @MainActor
    private static func topmost(from vc: UIViewController) -> UIViewController {
        if let presented = vc.presentedViewController {
            return topmost(from: presented)
        }
        if let nav = vc as? UINavigationController {
            return topmost(from: nav.visibleViewController ?? nav)
        }
        if let tab = vc as? UITabBarController {
            return topmost(from: tab.selectedViewController ?? tab)
        }
        return vc
    }
    #endif
}
