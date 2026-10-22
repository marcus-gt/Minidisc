import Foundation

/// A screen section the user can show, hide and reorder in Settings (Home, Discover).
/// Raw values are persisted: never rename an existing case.
nonisolated protocol LayoutSection: RawRepresentable, CaseIterable, Hashable, Identifiable, Sendable
where RawValue == String, AllCases == [Self] {}

/// Which sections of a screen are shown, and in what order. Persisted as JSON through `@AppStorage`.
///
/// Decoding is forgiving so the stored value survives app updates: unknown sections are dropped and
/// sections added in a later release appear, visible, in their default place (right after the
/// section that precedes them by default), so a new section lands where it was designed to go.
nonisolated struct SectionLayoutConfiguration<Section: LayoutSection>: Equatable, Sendable {
    private(set) var order: [Section]
    private(set) var hidden: Set<Section>

    static var `default`: Self { Self(order: Section.allCases, hidden: []) }

    init(order: [Section], hidden: Set<Section>) {
        self.order = Self.normalized(order)
        self.hidden = hidden
    }

    var visibleSections: [Section] { order.filter { !hidden.contains($0) } }

    func isVisible(_ section: Section) -> Bool { !hidden.contains(section) }

    mutating func setVisible(_ visible: Bool, for section: Section) {
        if visible { hidden.remove(section) } else { hidden.insert(section) }
    }

    mutating func setOrder(_ newOrder: [Section]) {
        order = Self.normalized(newOrder)
    }

    /// Explicit because of the `RawRepresentable` conformance below: without it the standard
    /// library's `==` for raw-representable types wins and compares encoded JSON strings instead.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.order == rhs.order && lhs.hidden == rhs.hidden
    }

    /// Removes duplicates and inserts any section missing from `order` right after the nearest
    /// section that precedes it in `allCases` (first when none does), keeping the user's own order.
    private static func normalized(_ order: [Section]) -> [Section] {
        var seen = Set<Section>()
        var result = order.filter { seen.insert($0).inserted }
        for (position, section) in Section.allCases.enumerated() where !seen.contains(section) {
            let predecessor = Section.allCases[..<position].last { seen.contains($0) }
            let index = predecessor.flatMap { result.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            result.insert(section, at: index)
            seen.insert(section)
        }
        return result
    }
}

extension SectionLayoutConfiguration: RawRepresentable {
    /// Encoded through a separate type: a `RawRepresentable` that encodes itself recurses inside `@AppStorage`.
    private struct Stored: Codable {
        var order: [String]
        var hidden: [String]
    }

    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return nil }
        self.init(
            order: stored.order.compactMap(Section.init(rawValue:)),
            hidden: Set(stored.hidden.compactMap(Section.init(rawValue:)))
        )
    }

    var rawValue: String {
        let stored = Stored(order: order.map(\.rawValue), hidden: hidden.map(\.rawValue).sorted())
        // Sorted keys keep the stored string canonical; JSONEncoder's key order is otherwise unstable.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(stored) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
