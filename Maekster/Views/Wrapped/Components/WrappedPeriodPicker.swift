import SwiftUI

struct WrappedPeriodPicker: View {
    @Binding var selectedPeriod: WrappedPeriod
    let availablePeriods: [WrappedPeriod]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MaeksterSpacing.xs) {
                ForEach(availablePeriods, id: \.self) { period in
                    let isSelected = period == selectedPeriod
                    Button {
                        selectedPeriod = period
                    } label: {
                        Text(shortLabel(for: period))
                            .font(isSelected ? .maeksterCellTitle : .maeksterCaption)
                            .foregroundStyle(isSelected ? Color.maeksterAccentText : .primary)
                            .padding(.horizontal, MaeksterSpacing.m)
                            .padding(.vertical, MaeksterSpacing.s)
                            .background(isSelected ? Color.maeksterAccent : Color.primary.opacity(0.08))
                            .clipShape(Capsule())
                            .animation(.easeInOut(duration: 0.15), value: isSelected)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, MaeksterSpacing.xs)
        }
        .contentMargins(.horizontal, MaeksterSpacing.l, for: .scrollContent)
        .padding(.horizontal, -MaeksterSpacing.l)
    }

    private func shortLabel(for period: WrappedPeriod) -> String {
        switch period {
        case .year(let year):
            return "\(year)"
        case .month(_, let month):
            return Calendar.current.shortMonthSymbols[month - 1]
        case .allTime:
            return period.displayName
        }
    }
}
