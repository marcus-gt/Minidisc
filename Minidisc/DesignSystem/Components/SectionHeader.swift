import SwiftUI

struct SectionHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.maeksterSectionTitle)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MaeksterSpacing.l)
            .padding(.vertical, MaeksterSpacing.s)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 0) {
        SectionHeader(title: "Albums")
        SectionHeader(title: "Top Tracks")
    }
}
