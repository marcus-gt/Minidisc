import SwiftUI

/// Every Wrapped year, newest first (#69), and the way into the monthly breakdowns.
struct WrappedYearlyListView: View {
    @Environment(\.appContainer) private var container
    @State private var firstYear: Int?

    private var years: [Int] { WrappedYears.years(firstYear: firstYear) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MaeksterSpacing.l) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: MaeksterSpacing.s)],
                    spacing: MaeksterSpacing.s
                ) {
                    WrappedYearTile(period: .allTime)
                    ForEach(years, id: \.self) { year in
                        WrappedYearTile(year: year)
                    }
                }

                NavigationLink {
                    WrappedView()
                } label: {
                    HStack(spacing: MaeksterSpacing.s) {
                        Image(systemName: "chart.bar.fill")
                            .font(.title2)
                            .foregroundStyle(Color.maeksterAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("View Listening Stats")
                                .font(.maeksterCellTitle)
                                .foregroundStyle(.primary)
                            Text("Monthly and annual breakdowns")
                                .font(.maeksterCaption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(MaeksterSpacing.m)
                    .background(Color.maeksterAccent.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: MaeksterCornerRadius.standard, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(MaeksterSpacing.l)
        }
        .maeksterContentWidth()
        .navigationTitle("Wrapped")
        .task {
            guard let container else { return }
            firstYear = await container.wrappedDataSource.firstYear(calendar: .current)
        }
    }
}
