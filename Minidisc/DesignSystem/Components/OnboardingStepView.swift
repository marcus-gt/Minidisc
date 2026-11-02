import SwiftUI

struct OnboardingStepView<Content: View>: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let stepIndex: Int
    let totalSteps: Int
    let onSkip: () -> Void
    let onContinue: () -> Void
    @ViewBuilder let content: () -> Content

    private var continueLabel: String {
        stepIndex == totalSteps - 1 ? "Done" : "Continue"
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
                .background(MaeksterColors.backgroundPrimary)
            content()
                .safeAreaInset(edge: .bottom) {
                    bottomActions
                }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: MaeksterSpacing.m) {
            ZStack {
                Circle()
                    .fill(MaeksterColors.accentBackground)
                    .frame(width: 60, height: 60)
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(MaeksterColors.accent)
            }

            VStack(spacing: MaeksterSpacing.xs) {
                Text(title)
                    .font(.system(.title3, weight: .bold))
                    .foregroundStyle(MaeksterColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(MaeksterColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .padding(.horizontal, MaeksterSpacing.xxxl)

            progressDots
        }
        .padding(.top, MaeksterSpacing.xxl)
        .padding(.bottom, MaeksterSpacing.l)
    }

    // MARK: - Progress dots

    private var progressDots: some View {
        HStack(spacing: MaeksterSpacing.s) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Capsule()
                    .fill(i == stepIndex ? MaeksterColors.accent : Color.secondary.opacity(0.3))
                    .frame(width: i == stepIndex ? 20 : 6, height: 6)
                    .animation(.easeInOut(duration: 0.25), value: stepIndex)
            }
        }
    }

    // MARK: - Bottom actions

    private var bottomActions: some View {
        VStack(spacing: MaeksterSpacing.m) {
            Button(action: onContinue) {
                Text(continueLabel)
                    .font(.system(.body, design: .default, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(MaeksterColors.accent)

            Button("Skip", action: onSkip)
                .font(.subheadline)
                .foregroundStyle(MaeksterColors.textSecondary)
        }
        .padding(.horizontal, MaeksterSpacing.xxxl)
        .padding(.top, MaeksterSpacing.l)
        .padding(.bottom, MaeksterSpacing.xxl)
        .background(.regularMaterial)
    }
}
