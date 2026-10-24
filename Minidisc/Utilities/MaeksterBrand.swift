import Foundation

/// How the app identifies itself to external services (ListenBrainz, LRCLIB, image providers).
/// The name is always lowercase. See `Branding/README.md`.
nonisolated enum MaeksterBrand {
    static let name = "maekster"
    static let repositoryURL = "https://github.com/marcus-gt/Minidisc"

    /// `maekster/<version> (https://github.com/marcus-gt/Minidisc)`, sent as the User-Agent.
    static let userAgent = userAgent(
        version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    )

    static func userAgent(version: String) -> String {
        "\(name)/\(version) (\(repositoryURL))"
    }
}
