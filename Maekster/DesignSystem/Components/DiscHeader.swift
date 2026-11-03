import SwiftUI

/// Separates the discs of a multi-disc album in a track list.
struct DiscHeader: View {
    let discNumber: Int
    var title: String?

    var body: some View {
        HStack(spacing: MaeksterSpacing.s) {
            Image(systemName: "opticaldisc")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Disc \(discNumber)")
                .font(.maeksterSectionTitle)
            if let title, !title.isEmpty {
                Text(verbatim: title)
                    .font(.maeksterCellSubtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, MaeksterSpacing.l)
        .padding(.top, MaeksterSpacing.l)
        .padding(.bottom, MaeksterSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    DiscHeader(discNumber: 2, title: "Live at the Fillmore")
        .background(Color.black)
        .environment(\.colorScheme, .dark)
}
