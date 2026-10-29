import SwiftUI

struct ArtistSortMenu: View {
    @Binding var sort: ArtistSort
    var options: [ArtistSort] = ArtistSort.allCases

    var body: some View {
        Menu {
            Picker("Sort By", selection: $sort) {
                ForEach(options, id: \.self) { option in
                    Label(option.label, systemImage: option.systemImage).tag(option)
                }
            }
        } label: {
            Label(sort.label, systemImage: "arrow.up.arrow.down")
        }
    }
}
