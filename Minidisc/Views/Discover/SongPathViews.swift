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

/// The Discover (and optional Home) card (#65): the path itself. Tap From or To to choose an end,
/// set the length and play, without opening a sheet.
struct SongPathCard: View {
    @Environment(\.appContainer) private var container
    @State private var editing: Side?
    @State private var isBuilding = false

    private enum Side: String, Identifiable {
        case from, to
        var id: String { rawValue }
    }

    private var launcher: SongPathLauncher? { container?.songPathLauncher }
    /// The chosen start, or what's playing.
    private var from: SongPathService.End? { launcher?.cardFrom ?? Self.nowPlaying(container) }
    private var to: SongPathService.End? { launcher?.cardTo }
    private var length: Binding<Double> {
        Binding(get: { launcher?.cardLength ?? Double(SongPathService.defaultLength) },
                set: { launcher?.cardLength = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
            HStack {
                Label("Song Path", systemImage: SongPathSheet.symbol)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Swap", systemImage: "arrow.up.arrow.down") {
                    let (oldFrom, oldTo) = (from, to)
                    launcher?.cardFrom = oldTo
                    launcher?.cardTo = oldFrom
                }
                .labelStyle(.iconOnly)
                .font(.subheadline.weight(.semibold))
                .disabled(from == nil && to == nil)
            }
            .foregroundStyle(.white.opacity(0.85))
            VStack(spacing: 0) {
                endRow(.from, end: from)
                Divider().overlay(.white.opacity(0.2)).padding(.leading, Self.tileArt + MinidiscSpacing.s * 2)
                endRow(.to, end: to)
            }
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: MinidiscCornerRadius.s))
            HStack(spacing: MinidiscSpacing.m) {
                Text("\(Int(length.wrappedValue)) songs")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize()
                Slider(value: length,
                       in: Double(SongPathService.lengthRange.lowerBound)...Double(SongPathService.lengthRange.upperBound),
                       step: 1)
                    .tint(.white)
                    .accessibilityLabel(Text("Length"))
                    .accessibilityValue(Text("\(Int(length.wrappedValue)) songs"))
                playButton
            }
        }
        .foregroundStyle(.white)
        .padding(MinidiscSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Self.gradientStart, Color(red: 0.16, green: 0.52, blue: 0.58)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: MinidiscCornerRadius.standard))
        .accessibilityIdentifier("discover.songPath")
        .padding(.horizontal, MinidiscSpacing.l)
        .sheet(item: $editing) { side in
            NavigationStack {
                SongPathEndPicker(selection: binding(for: side), other: side == .from ? to : from)
            }
        }
    }

    private static let tileArt: CGFloat = 32
    private static let playSize: CGFloat = 36
    private static let gradientStart = Color(red: 0.07, green: 0.20, blue: 0.36)

    private var canPlay: Bool { SongPathService.canBuild(from: from, to: to) }

    private var playButton: some View {
        Button {
            Task { await play() }
        } label: {
            Group {
                if isBuilding {
                    ProgressView().tint(Self.gradientStart)
                } else {
                    Image(systemName: "play.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Self.gradientStart)
                }
            }
            .frame(width: Self.playSize, height: Self.playSize)
            .background(.white, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canPlay || isBuilding)
        .opacity(canPlay ? 1 : 0.5)
        .accessibilityLabel(Text("Play"))
        .accessibilityHint("Play a path of songs from one song or mood to another")
    }

    private func binding(for side: Side) -> Binding<SongPathService.End?> {
        Binding(get: { side == .from ? from : to },
                set: { if side == .from { launcher?.cardFrom = $0 } else { launcher?.cardTo = $0 } })
    }

    /// An end as a tappable row: cover or mood, its name, and "From · artist" underneath.
    private func endRow(_ side: Side, end: SongPathService.End?) -> some View {
        Button { editing = side } label: {
            HStack(spacing: MinidiscSpacing.s) {
                Group {
                    switch end {
                    case .song(let song):
                        CoverArtCard(id: song.coverArtId ?? song.id, size: Self.tileArt, cornerRadius: MinidiscCornerRadius.xs)
                    case .mood(let mood):
                        Image(systemName: mood.wrappedSymbol)
                            .font(.subheadline.weight(.semibold))
                            .frame(width: Self.tileArt, height: Self.tileArt)
                            .background(mood.wrappedColor.opacity(0.85), in: RoundedRectangle(cornerRadius: MinidiscCornerRadius.xs))
                    case nil:
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: Self.tileArt, height: Self.tileArt)
                            .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: MinidiscCornerRadius.xs))
                    }
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(end.map { $0.name } ?? String(localized: "Choose a song or mood"))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(detail(side, end: end))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, MinidiscSpacing.s)
            .padding(.vertical, MinidiscSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "From · Bill Evans", "To · Mood", or just "From" before anything is chosen.
    private func detail(_ side: Side, end: SongPathService.End?) -> String {
        let label = side == .from ? String(localized: "From") : String(localized: "To")
        switch end {
        case .song(let song): return song.artist.map { "\(label) · \($0)" } ?? label
        case .mood: return "\(label) · \(String(localized: "Mood"))"
        case nil: return label
        }
    }

    private func play() async {
        guard let container, let from, let to else { return }
        isBuilding = true
        defer { isBuilding = false }
        if let message = await SongPathSheet.play(from: from, to: to, length: Int(length.wrappedValue), container: container) {
            container.toastService.showError(message)
        } else {
            HapticFeedback.medium.trigger()
        }
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
            SongPathEndPicker(selection: end, other: other)
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
        message = await Self.play(from: from, to: to, length: Int(length), container: container)
        if message == nil {
            HapticFeedback.medium.trigger()
            dismiss()
        }
    }

    /// Builds and plays the path. Returns what went wrong for the user, or nil when it plays
    /// (or was cancelled).
    static func play(from: SongPathService.End, to: SongPathService.End, length: Int,
                     container: AppContainer) async -> String? {
        do {
            let songs = try await container.songPathService.path(from: from, to: to, length: length)
            try await container.playerService.playUntilEnd(songs, source: .songPath(from: from.name, to: to.name))
            return nil
        } catch SongPathService.PathError.noPath {
            return String(localized: "AudioMuse found no path between these. Try other ends or a longer path.")
        } catch SongPathService.PathError.unavailable {
            return String(localized: "Song Path needs AudioMuse. Set it up in Settings › Integrations.")
        } catch {
            guard !UserFacingError.isCancellation(error) else { return nil }
            Logger.moodPlaylists.error("[SONG-PATH] failed: \(error, privacy: .public)")
            return String(localized: "Couldn't build the path. Check that AudioMuse is reachable and try again.")
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
    /// The path's other end: a mood there rules out a mood here, and Surprise Me avoids its song.
    let other: SongPathService.End?

    @Environment(\.appContainer) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [DisplayableSong] = []
    @State private var choosingMood = false
    @State private var suggestions: SongPathService.Suggestions?
    @State private var isSurprising = false

    private var moodAllowed: Bool { other?.isMood != true }

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
                if query.isEmpty {
                    suggestionSections
                } else {
                    Section {
                        ForEach(results) { songRow($0) }
                    }
                }
            }
        }
        .navigationTitle(choosingMood ? "Choose a Mood" : "Choose a Song")
        .navigationBarTitleDisplayModeInline()
        .searchable(text: $query, prompt: "Search songs")
        .task(id: query) { await search() }
        .task { suggestions = await container?.songPathService.suggestions() }
        .onAppear { if case .mood = selection { choosingMood = true } }
    }

    /// Before a search: what's playing, a random song, and the songs you're most likely to mean.
    @ViewBuilder
    private var suggestionSections: some View {
        if case .song(let playing)? = SongPathCard.nowPlaying(container) {
            Section("Now Playing") { songRow(playing) }
        }
        Section {
            Button {
                Task { await surprise() }
            } label: {
                HStack {
                    Label("Surprise Me", systemImage: "dice")
                    Spacer()
                    if isSurprising { ProgressView() }
                }
            }
            .disabled(isSurprising)
        }
        if let suggestions {
            suggestionSection("Recently Played", songs: suggestions.recent)
            suggestionSection("Your Top Songs", songs: suggestions.top)
            suggestionSection("Favorites", songs: suggestions.favorites)
        } else {
            Section {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func suggestionSection(_ title: LocalizedStringKey, songs: [DisplayableSong]) -> some View {
        if !songs.isEmpty {
            Section(title) {
                ForEach(songs) { songRow($0) }
            }
        }
    }

    private func surprise() async {
        guard let service = container?.songPathService else { return }
        isSurprising = true
        defer { isSurprising = false }
        let avoid: String? = if case .song(let song)? = other { song.id } else { nil }
        if let song = try? await service.surpriseSong(avoiding: avoid) {
            choose(.song(song))
        } else {
            container?.toastService.showError(String(localized: "Couldn't find a song. Try again."))
        }
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

#Preview("Card") {
    let container = try? AppContainer(inMemory: true, userDefaults: UserDefaults(suiteName: "song-path-preview")!)
    container?.songPathLauncher.cardFrom = .song(DisplayableSong(from: Song(id: "1", title: "Peace Piece", artist: "Bill Evans")))
    container?.songPathLauncher.cardTo = .mood(.relaxed)
    return ScrollView { SongPathCard() }
        .environment(\.appContainer, container)
        .environment(container!.artworkImageCache)
        .environment(container!.dominantColorExtractor)
}
