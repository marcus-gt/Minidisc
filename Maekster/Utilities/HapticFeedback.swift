import Foundation
#if os(iOS)
import UIKit
#endif

/// Use light for navigation, medium for playback, heavy for destructive actions,
/// selection for pickers, and the notification variants for operation outcomes.
/// Macs have no haptic engine for these, so `trigger()` does nothing there.
@MainActor
enum HapticFeedback {
    case light
    case medium
    case heavy
    case selection
    case success
    case warning
    case error

    func trigger() {
        #if os(iOS)
        switch self {
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .heavy:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        #endif
    }
}
