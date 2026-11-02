import SwiftUI

enum MaeksterCarouselMetrics {
    static let previewLimit = 10
    static let artistArtwork: CGFloat = 104
}

struct MaeksterShelf<Header: View, Content: View>: View {
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: MaeksterSpacing.s) {
            header()
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: MaeksterSpacing.m) {
                    content()
                }
                .scrollTargetLayout()
                .padding(.horizontal, MaeksterSpacing.l)
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

struct MaeksterCarouselHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let title: Text
    private let showsChevron: Bool
    private let horizontalPadding: CGFloat

    init(
        _ title: LocalizedStringResource,
        showsChevron: Bool,
        horizontalPadding: CGFloat = MaeksterSpacing.l
    ) {
        self.title = Text(title)
        self.showsChevron = showsChevron
        self.horizontalPadding = horizontalPadding
    }

    fileprivate init(
        title: Text,
        showsChevron: Bool,
        horizontalPadding: CGFloat
    ) {
        self.title = title
        self.showsChevron = showsChevron
        self.horizontalPadding = horizontalPadding
    }

    var body: some View {
        HStack(alignment: .center, spacing: MaeksterSpacing.s) {
            title
                .font(.maeksterShelfTitle)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)

            Spacer(minLength: MaeksterSpacing.s)

            if showsChevron {
                Image(systemName: "chevron.forward")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 24, height: 24)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, MaeksterSpacing.xs)
    }
}

/// A shelf title that becomes a full-width navigation link when the shelf has hidden content.
struct MaeksterCarouselHeaderLink<Destination: View>: View {
    private let title: Text
    private let horizontalPadding: CGFloat
    private let destination: Destination
    private let showsNavigation: Bool

    init(
        _ title: LocalizedStringResource,
        itemCount: Int,
        visibleLimit: Int = MaeksterCarouselMetrics.previewLimit,
        hasMore: Bool = false,
        horizontalPadding: CGFloat = MaeksterSpacing.l,
        @ViewBuilder destination: () -> Destination
    ) {
        self.title = Text(title)
        self.horizontalPadding = horizontalPadding
        self.destination = destination()
        showsNavigation = itemCount > visibleLimit || hasMore
    }

    init(
        verbatim title: String,
        itemCount: Int,
        visibleLimit: Int = MaeksterCarouselMetrics.previewLimit,
        hasMore: Bool = false,
        horizontalPadding: CGFloat = MaeksterSpacing.l,
        @ViewBuilder destination: () -> Destination
    ) {
        self.title = Text(verbatim: title)
        self.horizontalPadding = horizontalPadding
        self.destination = destination()
        showsNavigation = itemCount > visibleLimit || hasMore
    }

    @ViewBuilder
    var body: some View {
        if showsNavigation {
            NavigationLink {
                destination
            } label: {
                header(showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityHint("See all")
        } else {
            header(showsChevron: false)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func header(showsChevron: Bool) -> some View {
        MaeksterCarouselHeader(
            title: title,
            showsChevron: showsChevron,
            horizontalPadding: horizontalPadding
        )
    }
}
