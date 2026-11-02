import OSLog
import SwiftSonic
import SwiftUI

/// Song Path needs AudioMuse on the active server, and the server itself (#65).
@MainActor
enum SongPathAvailability {
    static func isAvailable(_ container: AppContainer?) -> Bool {
        guard let container, container.serverState.isOnline else { return false }
        return container.serverState.activeServer?.audioMuseURL?.trimmingCharacters(in: .whitespaces).isEmpty == false
    }
}

/// The Discover (and optional Home) entry point (#65).
struct SongPathCard: View {
    @Environment(\.appContainer) private var container

    var body: some View {
        Button {
            container?.songPathLauncher.open(from: Self.nowPlaying(container), in: .main)
        } label: {
            HStack(spacing: MinidiscSpacing.m) {
                VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
                    Label("Song Path", systemImage: SongPathSheet.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text("From One Song to Another")
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Pick two songs or a mood, and AudioMuse finds the way between them")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: SongPathSheet.symbol)
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.white)
            .padding(MinidiscSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Color(red: 0.07, green: 0.20, blue: 0.36),
                                                 Color(red: 0.16, green: 0.52, blue: 0.58)],
                                       startPoint: .leading, endPoint: .trailing))
            .clipShape(RoundedRectangle(cornerRadius: MinidiscCornerRadius.standard))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Song Path")
        .accessibilityHint("Play a path of songs from one song or mood to another")
        .accessibilityIdentifier("discover.songPath")
        .padding(.horizontal, MinidiscSpacing.l)
    }

    /// The path starts from what's playing, when something is.
    static func nowPlaying(_ container: AppContainer?) -> SongPathService.End? {
        guard let track = container?.playerState.currentTrack, !track.isLocalFile,
              container?.playerState.isLiveStream != true else { return nil }
        return .song(track)
    }
}

/// From, To and length, then Play (#65). The path stops at its last song.
struct SongPathSheet: View {
    static let symbol = "point.topleft.down.to.point.bottomright.curvepath"

    @Environment(\.appContainer) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var from: SongPathService.End?
    @State private var to: SongPathService.End?
    @State private var length = Double(SongPathService.defaultLength)
    @State private var isBuilding = false
    @State private var message: String?

    init(from: SongPathService.End?) {
        _from = State(initialValue: from)
    }

    private var canPlay: Bool { SongPathService.canBuild(from: from, to: to) && !isBuilding }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    endLink("From", end: $from, other: to)
                    endLink("To", end: $to, other: from)
                } footer: {
                    Text("Either end can be a mood, but not both.")
                }
                Section {
                    VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
                        Text("\(Int(length)) songs")
                            .monospacedDigit()
                        Slider(value: $length, in: Double(SongPathService.lengthRange.lowerBound)...Double(SongPathService.lengthRange.upperBound), step: 1)
                            .accessibilityLabel(Text("Length"))
                            .accessibilityValue(Text("\(Int(length)) songs"))
                    }
                } header: {
                    Text("Length")
                } footer: {
                    Text("The path plays from the first song to the last, then stops.")
                }
                if let message {
                    Section {
                        Text(message).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Song Path")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isBuilding {
                        ProgressView()
                    } else {
                        Button("Play") { Task { await play() } }
                            .disabled(!canPlay)
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Swap", systemImage: "arrow.up.arrow.down") { (from, to) = (to, from) }
                        .disabled(from == nil && to == nil)
                }
            }
        }
    }

    private func endLink(_ title: LocalizedStringKey, end: Binding<SongPathService.End?>,
                         other: SongPathService.End?) -> some View {
        NavigationLink {
            SongPathEndPicker(selection: end, moodAllowed: other?.isMood != true)
        } label: {
            LabeledContent(title) {
                if let value = end.wrappedValue {
                    SongPathEndLabel(end: value)
                } else {
                    Text("Choose").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func play() async {
        guard let container, let from, let to else { return }
        isBuilding = true
        message = nil
        defer { isBuilding = false }
        do {
            let songs = try await container.songPathService.path(from: from, to: to, length: Int(length))
            try await container.playerService.playUntilEnd(songs, source: .songPath(from: from.name, to: to.name))
            HapticFeedback.medium.trigger()
            dismiss()
        } catch SongPathService.PathError.noPath {
            message = String(localized: "AudioMuse found no path between these. Try other ends or a longer path.")
        } catch SongPathService.PathError.unavailable {
            message = String(localized: "Song Path needs AudioMuse. Set it up in Settings › Integrations.")
        } catch {
            guard !UserFacingError.isCancellation(error) else { return }
            Logger.moodPlaylists.error("[SONG-PATH] failed: \(error, privacy: .public)")
            message = String(localized: "Couldn't build the path. Check that AudioMuse is reachable and try again.")
        }
    }
}

/// A chosen end: the song with its cover, or the mood.
private struct SongPathEndLabel: View {
    let end: SongPathService.End

    var body: some View {
        switch end {
        case .song(let song):
            HStack(spacing: MinidiscSpacing.s) {
                CoverArtCard(id: song.coverArtId ?? song.id, size: 28, cornerRadius: MinidiscCornerRadius.xs)
                Text(song.title).lineLimit(1)
            }
        case .mood(let mood):
            Label { Text(mood.title) } icon: { Image(systemName: mood.wrappedSymbol) }
        }
    }
}

/// Pick a song from the library (searched as you type, or the one playing) or a mood.
private struct SongPathEndPicker: View {
    @Binding var selection: SongPathService.End?
    let moodAllowed: Bool

    @Environment(\.appContainer) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [DisplayableSong] = []
    @State private var choosingMood = false

    var body: some View {
        List {
            if moodAllowed {
                Picker("Kind", selection: $choosingMood) {
                    Text("Song").tag(false)
                    Text("Mood").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }
            if choosingMood {
                ForEach(SongPathService.moods) { mood in
                    Button { choose(.mood(mood)) } label: {
                        Label { Text(mood.title).foregroundStyle(.primary) } icon: {
                            Image(systemName: mood.wrappedSymbol).foregroundStyle(mood.wrappedColor)
                        }
                    }
                }
            } else {
                if query.isEmpty, case .song(let playing)? = SongPathCard.nowPlaying(container) {
                    Section("Now Playing") { songRow(playing) }
                }
                Section {
                    ForEach(results) { songRow($0) }
                }
            }
        }
        .navigationTitle(choosingMood ? "Choose a Mood" : "Choose a Song")
        .navigationBarTitleDisplayModeInline()
        .searchable(text: $query, prompt: "Search songs")
        .task(id: query) { await search() }
        .onAppear { if case .mood = selection { choosingMood = true } }
    }

    private func songRow(_ song: DisplayableSong) -> some View {
        Button { choose(.song(song)) } label: {
            HStack(spacing: MinidiscSpacing.m) {
                CoverArtCard(id: song.coverArtId ?? song.id, size: 40, cornerRadius: MinidiscCornerRadius.xs)
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title).foregroundStyle(.primary).lineLimit(1)
                    if let artist = song.artist {
                        Text(artist).font(.minidiscCaption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }

    private func choose(_ end: SongPathService.End) {
        HapticFeedback.light.trigger()
        selection = end
        dismiss()
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, let library = container?.libraryService else {
            results = []
            return
        }
        // Debounce typing.
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled, let found = try? await library.search(trimmed) else { return }
        results = (found.song ?? []).filter { !($0.isDir ?? false) }.prefix(50).map { DisplayableSong(from: $0) }
    }
}

extension View {
    /// Presents the Song Path sheet when the launcher asks this host for it (#65).
    func songPathSheet(_ host: SheetHost, container: AppContainer?) -> some View {
        sheet(item: Binding(
            get: { container?.songPathLauncher.request.flatMap { $0.host == host ? $0 : nil } },
            set: { if $0 == nil { container?.songPathLauncher.request = nil } }
        )) { request in
            SongPathSheet(from: request.from)
        }
    }
}
