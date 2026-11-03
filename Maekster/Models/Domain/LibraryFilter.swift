import Foundation

/// The in-place filter on Library lists: case- and diacritic-insensitive substring matching.
nonisolated enum LibraryFilter {
    /// The trimmed query, or `nil` when the field holds nothing to filter by.
    static func query(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `items` narrowed to those matching `text`; everything when `text` is blank.
    static func filter<Item>(_ items: [Item], by text: String, fields: (Item) -> [String?]) -> [Item] {
        guard let query = query(text) else { return items }
        return items.filter { item in fields(item).contains { $0?.localizedStandardContains(query) == true } }
    }
}
