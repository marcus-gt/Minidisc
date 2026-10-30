import SwiftUI
import OSLog

struct AudioMuseSettingsView: View {
    @Environment(\.appContainer) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var urlInput = ""
    @State private var tokenInput = ""
    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var showDisconnectAlert = false
    @State private var didLoad = false

    private enum TestResult: Equatable {
        case success(trackCount: Int)
        case failure(String)
    }

    private var activeServer: ServerSnapshot? { container?.serverState.activeServer }
    private var isConnected: Bool { activeServer?.audioMuseURL?.isEmpty == false }

    var body: some View {
        Form {
            aboutSection
            if activeServer == nil {
                Section { Text("No server configured.").foregroundStyle(.secondary) }
            } else {
                connectionSection
                statusSection
            }
        }
        .navigationTitle("AudioMuse")
        .navigationBarTitleDisplayModeInline()
        .task {
            guard !didLoad else { return }
            didLoad = true
            urlInput = activeServer?.audioMuseURL ?? ""
            tokenInput = (try? await container?.serverService.activeConnection())??.credentials.audioMuseToken ?? ""
        }
    }

    // MARK: - Sections

    private var aboutSection: some View {
        Section {
            Text("AudioMuse-AI analyses how your music actually sounds, which lets maekster build a mood radio from the sound rather than from tags.")
                .font(.minidiscCaption)
                .foregroundStyle(.secondary)
            Text("Without it, mood radios still work, built from your library's genre, BPM and mood tags. The match is rougher.")
                .font(.minidiscCaption)
                .foregroundStyle(.secondary)
            Link("Learn about AudioMuse-AI →", destination: URL(string: "https://github.com/NeptuneHub/AudioMuse-AI")!)
                .font(.minidiscCaption)
        }
    }

    private var connectionSection: some View {
        Section {
            TextField("", text: $urlInput, prompt: Text(verbatim: "http://nas.local:8000"))
                .textContentType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            SecureField("API token (optional)", text: $tokenInput)
                .textContentType(.password)
                .autocorrectionDisabled()

            Button {
                Task { await testAndSave() }
            } label: {
                HStack {
                    Text(isConnected ? "Test and Update" : "Connect")
                    if isTesting {
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(urlInput.trimmingCharacters(in: .whitespaces).isEmpty || isTesting)

            if let testResult {
                switch testResult {
                case .success(let count):
                    Label("Connected — \(count) tracks matched a test search.", systemImage: "checkmark.circle")
                        .font(.minidiscCaption)
                        .foregroundStyle(.green)
                case .failure(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.minidiscCaption)
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Server")
        } footer: {
            Text("Leave the token empty if your AudioMuse instance runs without authentication.")
        }
    }

    private var statusSection: some View {
        Section {
            LabeledContent("Matching") {
                Text(isConnected ? "Sonic analysis" : "Library tags")
            }
            if isConnected {
                Button("Disconnect", role: .destructive) { showDisconnectAlert = true }
            }
        } footer: {
            Text("Mood radios on Discover use sonic analysis when AudioMuse is connected, and your library tags otherwise.")
        }
        .alert("Disconnect AudioMuse?", isPresented: $showDisconnectAlert) {
            Button("Disconnect", role: .destructive) { Task { await disconnect() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Mood radios will use your library tags.")
        }
    }

    // MARK: - Actions

    private func testAndSave() async {
        guard let container, let server = activeServer else { return }
        isTesting = true
        testResult = nil
        defer { isTesting = false }

        let url = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let client = AudioMuseClient(urlString: url, token: token.isEmpty ? nil : token) else {
            testResult = .failure(String(localized: "That does not look like a valid address."))
            return
        }

        do {
            // Test through the provider to include metadata recovery for unusable AudioMuse IDs.
            let provider = AudioMuseTrackProvider(
                client: client,
                resolver: SubsonicTrackResolver(libraryService: container.libraryService)
            )
            let tracks = try await provider.trackIds(for: .chill, limit: 5)
            Logger.moodPlaylists.info("[AUDIOMUSE-TEST] \(tracks.count, privacy: .public) usable tracks, ids=\(tracks.prefix(3).joined(separator: ","), privacy: .public)")
            guard !tracks.isEmpty else {
                testResult = .failure(String(localized: "Connected, but the search returned nothing. Has the sonic analysis been run?"))
                return
            }
            try await container.serverService.setAudioMuseConfig(serverId: server.id, urlString: url, token: token)
            testResult = .success(trackCount: tracks.count)
        } catch let error as AudioMuseError {
            Logger.moodPlaylists.warning("[AUDIOMUSE-TEST] failed: \(String(describing: error), privacy: .public)")
            testResult = .failure(message(for: error))
        } catch {
            Logger.moodPlaylists.warning("[AUDIOMUSE-TEST] failed: \(error, privacy: .public)")
            testResult = .failure(error.localizedDescription)
        }
    }

    private func disconnect() async {
        guard let container, let server = activeServer else { return }
        try? await container.serverService.setAudioMuseConfig(serverId: server.id, urlString: nil, token: nil)
        urlInput = ""
        tokenInput = ""
        testResult = nil
    }

    private func message(for error: AudioMuseError) -> String {
        switch error {
        case .searchDisabled(let serverMessage):
            return serverMessage ?? String(localized: "Sonic search is switched off on this AudioMuse instance.")
        case .notAnalysed:
            return String(localized: "AudioMuse has not analysed your library yet. Run an analysis, then try again.")
        case .unauthorized:
            return String(localized: "The API token was rejected.")
        case .internalIdsOnly:
            return String(localized: "AudioMuse found tracks, but none of them exist in your music library. Is it analysing the same collection?")
        case .badURL:
            return String(localized: "That does not look like a valid address.")
        case .notFound:
            return String(localized: "AudioMuse has no analysis for that track.")
        case .transport(let detail), .decoding(let detail):
            return detail
        }
    }
}
