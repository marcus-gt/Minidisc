import SwiftUI
import UIKit

struct OnboardingWelcomeView: View {
    let onServerConnected: () -> Void

    @Environment(\.appContainer) private var container
    @State private var viewModel: OnboardingViewModel?
    @State private var showingServerForm = false
    @State private var appeared = false
    @AppStorage("minidisc.localMusicEnabled") private var localMusicEnabled = false

    var body: some View {
        ZStack {
            MinidiscColors.backgroundPrimary.ignoresSafeArea()

            GeometryReader { geometry in
                ScrollView {
                    welcomeContent
                        .frame(minHeight: geometry.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .onAppear {
            guard viewModel == nil, let container else { return }
            viewModel = OnboardingViewModel(serverService: container.serverService)
            appeared = true
        }
        .onChange(of: container?.serverState.activeServer != nil) { _, connected in
            if connected { showingServerForm = false }
        }
        .sheet(isPresented: $showingServerForm, onDismiss: {
            if container?.serverState.activeServer != nil { onServerConnected() }
        }) {
            if let viewModel {
                NavigationStack { ServerFormView(viewModel: viewModel) }
            }
        }
    }

    private var welcomeContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: MinidiscSpacing.xl)

            BrandMarkHero(appeared: appeared)

            Spacer().frame(height: MinidiscSpacing.xxxxl)

            VStack(spacing: MinidiscSpacing.m) {
                Text("Your music.\nYour rules.")
                    .font(.system(.largeTitle, weight: .bold))
                    .foregroundStyle(MinidiscColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(4)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 24)
                    .animation(.spring(duration: 0.5, bounce: 0.3).delay(0.05), value: appeared)

                Text("Stream your library from your own server.\nNo subscriptions. No big tech.")
                    .font(.system(.body))
                    .foregroundStyle(MinidiscColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 24)
                    .animation(.spring(duration: 0.5, bounce: 0.3).delay(0.1), value: appeared)
            }
            .padding(.horizontal, MinidiscSpacing.xxxl)

            Spacer(minLength: MinidiscSpacing.xl)

            Button { localMusicEnabled = true } label: {
                Text("Use Local Files", tableName: "LocalMusic")
            }
            .padding(.bottom, MinidiscSpacing.l)

            getStartedButton
                .padding(.horizontal, MinidiscSpacing.xxxl)
                .padding(.bottom, MinidiscSpacing.xxxl)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 30)
                .animation(.spring(duration: 0.5, bounce: 0.3).delay(0.2), value: appeared)
        }
    }

    private var getStartedButton: some View {
        Button {
            triggerHaptic()
            showingServerForm = true
        } label: {
            Text("Get Started")
                .font(.system(.body, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(MinidiscColors.accent)
        .disabled(viewModel == nil)
    }

    private func triggerHaptic() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

// MARK: - Brand Mark Hero

/// The maekster mark over a soft accent glow. It fades in with a slight scale on first appearance;
/// under Reduce Motion it is shown still, without the entrance.
private struct BrandMarkHero: View {
    let appeared: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let markWidth: CGFloat = 220
    private let glowDiameter: CGFloat = 300
    private let glowBlur: CGFloat = 60

    var body: some View {
        ZStack {
            Circle()
                .fill(MinidiscColors.accent.opacity(0.08))
                .frame(width: glowDiameter, height: glowDiameter)
                .blur(radius: glowBlur)
                .accessibilityHidden(true)

            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: markWidth)
                .accessibilityLabel(Text(verbatim: "maekster"))
        }
        .opacity(reduceMotion || appeared ? 1 : 0)
        .scaleEffect(reduceMotion || appeared ? 1 : 0.94)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.8), value: appeared)
    }
}
