import SwiftUI

struct EmptyStateView: View {
    struct Action {
        let label: LocalizedStringKey
        let handler: () -> Void
    }

    let systemImage: String
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    var action: Action? = nil

    var body: some View {
        VStack(spacing: MaeksterSpacing.l) {
            Image(systemName: systemImage)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)

            VStack(spacing: MaeksterSpacing.s) {
                Text(title)
                    .font(.maeksterSectionTitle)
                    .multilineTextAlignment(.center)
                if let subtitle {
                    Text(subtitle)
                        .font(.maeksterBody)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
            }

            if let action {
                Button(action.label, action: action.handler)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.maeksterAccent)
            }
        }
        .padding(MaeksterSpacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("With action") {
    EmptyStateView(
        systemImage: "magnifyingglass",
        title: "No Results",
        subtitle: "Try another category or search term.",
        action: .init(label: "Clear") {}
    )
}

#Preview("Minimal") {
    EmptyStateView(systemImage: "arrow.down.circle", title: "No Downloads")
        .preferredColorScheme(.dark)
}

/// Shown in place of a Library list when its filter matches nothing.
struct FilterNoResultsView: View {
    let query: String

    var body: some View {
        EmptyStateView(
            systemImage: "magnifyingglass",
            title: "No Results",
            subtitle: "Nothing matches “\(query)”."
        )
    }
}
