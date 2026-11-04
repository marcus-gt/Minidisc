import SwiftUI

struct CoverCardMetadata: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    var subtitle: String? = nil
    var detail: String? = nil
    var titleColor: Color = .primary
    var secondaryColor: Color = .secondary
    /// Lines the title may wrap to; the Mac's album grids allow two, like the Music app.
    var titleLineLimit = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title)
                .font(.maeksterCellTitle)
                .foregroundStyle(titleColor)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : titleLineLimit)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let subtitle, !subtitle.isEmpty {
                Text(verbatim: subtitle)
                    .font(.maeksterCaption)
                    .foregroundStyle(secondaryColor)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .truncationMode(.tail)
            }

            if let detail, !detail.isEmpty {
                Text(verbatim: detail)
                    .font(.maeksterCaption2)
                    .foregroundStyle(secondaryColor)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .truncationMode(.tail)
            }
        }
        .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
    }
}
