import SwiftUI
import SwiftSonic

struct LyricsView: View {
    @Bindable var viewModel: LyricsViewModel

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .loaded(let structured):
                loadedContent(structured)

            case .empty:
                emptyState

            case .unsupported:
                unsupportedState

            case .error(let message):
                errorState(message)
            }
        }
        .onAppear { viewModel.setVisible(true) }
        .onDisappear { viewModel.setVisible(false) }
        .onChange(of: viewModel.isPlaying) { _, _ in viewModel.reconcileTracking() }
        .animation(.easeInOut(duration: 0.25), value: viewModel.isFollowing)
    }

    // MARK: - Loaded

    @ViewBuilder
    private func loadedContent(_ structured: StructuredLyrics) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 32) {
                    ForEach(Array(structured.line.enumerated()), id: \.offset) { index, line in
                        LyricsLineView(
                            value: line.value,
                            index: index,
                            currentIndex: viewModel.currentLineIndex,
                            isSynced: structured.synced,
                            // Reading mode: no blur, so any line can be read while scrolling.
                            isFollowing: viewModel.isFollowing,
                            isTappable: structured.synced && line.start != nil,
                            onTap: { viewModel.userTapped(lineIndex: index) }
                        )
                        .id(index)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 200)
            }
            .scrollIndicators(.hidden)
            .onChange(of: viewModel.currentLineIndex) { _, newIndex in
                guard viewModel.isFollowing, let newIndex else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
            .onScrollPhaseChange { _, newPhase in
                if newPhase == .interacting { viewModel.userStartedScrolling() }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                header
            }
            .overlay(alignment: .bottom) {
                followButton(proxy: proxy)
            }
        }
    }

    // MARK: - Header

    /// Only a language choice, and only when the lyrics really come in more than one language.
    @ViewBuilder
    private var header: some View {
        if viewModel.availableLanguages.count > 1 {
            HStack(spacing: 16) {
                Menu {
                    ForEach(viewModel.availableLanguages, id: \.self) { lang in
                        Button(displayName(for: lang)) {
                            viewModel.selectLanguage(lang)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                        Text(displayName(for: viewModel.selectedLanguage ?? "und"))
                    }
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.8))
                }
                .accessibilityLabel(Text("Lyrics language"))

                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
        }
    }

    /// Scrolling by hand stops the lyrics following the music; this brings them back.
    @ViewBuilder
    private func followButton(proxy: ScrollViewProxy) -> some View {
        if !viewModel.isFollowing, viewModel.currentLineIndex != nil {
            Button {
                viewModel.resumeFollowing()
                if let index = viewModel.currentLineIndex {
                    withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(index, anchor: .center) }
                }
            } label: {
                Label("Follow", systemImage: "arrow.down.circle.fill")
                    .font(.minidiscCellTitle)
                    .padding(.horizontal, MinidiscSpacing.m)
                    .padding(.vertical, MinidiscSpacing.s)
                    .background(.ultraThinMaterial, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.bottom, MinidiscSpacing.m)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Empty states

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No lyrics available")
                .font(.minidiscDetailTitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unsupportedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Lyrics not supported")
                .font(.minidiscDetailTitle)
                .foregroundStyle(.secondary)
            Text("Update your Navidrome server to enable the songLyrics extension")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.octagon")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Failed to load lyrics")
                .font(.minidiscDetailTitle)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func displayName(for lang: String) -> String {
        guard lang != "und", lang != "xxx" else { return String(localized: "Original") }
        return Locale.current.localizedString(forLanguageCode: lang)?.capitalized ?? lang.uppercased()
    }
}
