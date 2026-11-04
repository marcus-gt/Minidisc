import Foundation

/// Platform facts views branch on, so `#if os(...)` stays out of view bodies.
nonisolated enum MaeksterPlatform {
    /// Whether the device can be on a cellular path. A Mac never is (a phone's hotspot reaches it as
    /// Wi-Fi), so settings that only apply on cellular are hidden there.
    static let hasCellularData: Bool = {
        #if os(macOS)
        false
        #else
        true
        #endif
    }()
}
