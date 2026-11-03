import SwiftUI

extension PlaylistListSort {
    var label: LocalizedStringKey {
        switch self {
        case .lastUsed: "Last Used"
        case .recentlyCreated: "Recently Created"
        case .name: "Name"
        }
    }

    var systemImage: String {
        switch self {
        case .lastUsed: "clock.arrow.circlepath"
        case .recentlyCreated: "calendar"
        case .name: "textformat"
        }
    }
}

struct PlaylistListSortMenu: View {
    @Binding var sort: PlaylistListSort

    var body: some View {
        Menu {
            Picker("Sort By", selection: $sort) {
                ForEach(PlaylistListSort.allCases) { option in
                    Label(option.label, systemImage: option.systemImage).tag(option)
                }
            }
        } label: {
            Label("Sort By", systemImage: "arrow.up.arrow.down")
        }
    }
}
