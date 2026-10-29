import SwiftUI

/// The ↕︎ Sort button for a Library list (#43), the same in look and place as the other lists'.
struct LibrarySortMenu<Option: LibrarySortOption>: View {
    @Binding var sort: Option

    var body: some View {
        Menu {
            Picker("Sort By", selection: $sort) {
                ForEach(Array(Option.allCases), id: \.self) { option in
                    Label { Text(option.title) } icon: { Image(systemName: option.systemImage) }.tag(option)
                }
            }
        } label: {
            Label { Text(sort.title) } icon: { Image(systemName: "arrow.up.arrow.down") }
        }
    }
}
