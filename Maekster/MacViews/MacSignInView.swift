import SwiftUI

/// Adds the first server. Same form, view model and connection test as the iPhone onboarding; once
/// the server is active, `RootView` switches to the main window.
struct MacSignInView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: OnboardingViewModel?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: MaeksterSpacing.l) {
                Image("BrandMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                Text("Your music.\nYour rules.")
                    .font(.largeTitle.bold())
                Text("Stream your library from your own server.\nNo subscriptions. No big tech.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(MaeksterSpacing.xxxl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            if let viewModel {
                ServerFormView(viewModel: viewModel)
                    .formStyle(.grouped)
                    .frame(width: 440)
            }
        }
        .task {
            guard viewModel == nil, let container else { return }
            viewModel = OnboardingViewModel(serverService: container.serverService)
        }
    }
}
