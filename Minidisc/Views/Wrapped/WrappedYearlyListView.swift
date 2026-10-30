import SwiftUI

/// Every Wrapped year, newest first (#69), and the way into the monthly breakdowns.
struct WrappedYearlyListView: View {
    @Environment(\.appContainer) private var container
    @State private var firstYear: Int?

    private var years: [Int] { WrappedYears.years(firstYear: firstYear) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MinidiscSpacing.l) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: MinidiscSpacing.s)],
                    spacing: MinidiscSpacing.s
                ) {
                    ForEach(years, id: \.self) { year in
                        WrappedYearTile(year: year)
                    }
                }

                NavigationLink {
                    WrappedView()
                } label: {
                    HStack(spacing: MinidiscSpacing.s) {
                        Image(systemName: "chart.bar.fill")
                            .font(.title2)
                            .foregroundStyle(Color.minidiscAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("View Listening Stats")
                                .font(.minidiscCellTitle)
                                .foregroundStyle(.primary)
                            Text("Monthly and annual breakdowns")
                                .font(.minidiscCaption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(MinidiscSpacing.m)
                    .background(Color.minidiscAccent.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: MinidiscCornerRadius.standard, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(MinidiscSpacing.l)
        }
        .minidiscContentWidth()
        .navigationTitle("Wrapped")
        .task {
            guard let container else { return }
            firstYear = await container.wrappedDataSource.firstYear(calendar: .current)
        }
    }
}
