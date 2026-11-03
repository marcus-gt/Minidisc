import SwiftUI

enum LidarrFormat {
    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .binary
        return f
    }()

    static func size(_ bytes: Int64) -> String { byteFormatter.string(fromByteCount: bytes) }

    static func age(days: Int) -> String {
        if days < 1 { return "today" }
        if days < 30 { return "\(days)d" }
        if days < 365 { return "\(days / 30)mo" }
        return "\(days / 365)y"
    }
}

struct LidarrReleaseDetailView: View {
    let release: LidarrRelease
    let client: LidarrClient
    /// What the interactive search was scoped to, used to force the grab target when Lidarr cannot
    /// parse the release itself.
    let scope: LidarrReleaseScope

    @Environment(\.appContainer) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var isGrabbing = false
    @State private var showGrabConfirm = false
    @State private var showAlbumPicker = false

    private var overrideAlbumId: Int? {
        if let id = release.albumId { return id }
        if case .album(let album) = scope { return album.id }
        return nil
    }
    private var overrideArtistId: Int? {
        if let id = release.artistId { return id }
        switch scope {
        case .album(let album):   return album.artistId
        case .artist(let artist): return artist.id
        }
    }
    private var pickerArtistId: Int? {
        if case .artist(let artist) = scope { return artist.id }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MaeksterSpacing.l) {
                headerSection
                if release.isRejected { rejectionBanner }
                actionButtons
                infoSection
            }
            .padding(.horizontal, MaeksterSpacing.l)
            .padding(.top, MaeksterSpacing.xl)
            .padding(.bottom, MaeksterSpacing.l)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .alert("Grab Release", isPresented: $showGrabConfirm) {
            Button("Grab") { Task { await grab() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Lidarr could not match this release to an artist and album, so it may not import on its own. Grab it anyway?")
        }
        .sheet(isPresented: $showAlbumPicker) {
            if let artistId = pickerArtistId {
                LidarrAlbumPickerSheet(artistId: artistId, client: client) { albumId in
                    showAlbumPicker = false
                    Task { await grab(albumId: albumId) }
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: MaeksterSpacing.s) {
            HStack(alignment: .top, spacing: MaeksterSpacing.m) {
                VStack(alignment: .leading, spacing: MaeksterSpacing.xs) {
                    if let flag = release.flagLabel {
                        Text(flag)
                            .font(.maeksterCaption)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.maeksterAccent)
                    }
                    Text(release.title)
                        .font(.maeksterDetailTitle)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: MaeksterSpacing.xs) {
                        if let quality = release.qualityName { Text(quality) }
                        if let size = release.size {
                            Text("·")
                            Text(LidarrFormat.size(size))
                        }
                        if let age = release.age {
                            Text("·")
                            Text(LidarrFormat.age(days: age))
                        }
                    }
                    .font(.maeksterCaption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(role: .close) {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .tint(.primary)
                .accessibilityLabel("Close")
            }

            if !release.flags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: MaeksterSpacing.xs) {
                        ForEach(release.flags, id: \.self) { flag in
                            Text(flag)
                                .font(.maeksterCaption)
                                .padding(.horizontal, MaeksterSpacing.s)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                        }
                    }
                }
            }
        }
    }

    // MARK: - Rejection

    private var rejectionBanner: some View {
        VStack(alignment: .leading, spacing: MaeksterSpacing.xs) {
            Label("Release Rejected", systemImage: "exclamationmark.triangle.fill")
                .font(.maeksterCellTitle)
                .fontWeight(.bold)
                .foregroundStyle(.orange)
            ForEach(release.rejections ?? [], id: \.self) { reason in
                Text(reason)
                    .font(.maeksterCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MaeksterSpacing.m)
        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: MaeksterCornerRadius.standard))
    }

    // MARK: - Actions

    private var actionButtons: some View {
        HStack(spacing: MaeksterSpacing.m) {
            if let url = release.infoURL {
                Link(destination: url) {
                    Label("Website", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MaeksterSpacing.s)
                }
            }
            Button {
                handleDownloadTap()
            } label: {
                HStack {
                    if isGrabbing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.down.circle")
                    }
                    Text("Download")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, MaeksterSpacing.s)
            }
            .disabled(isGrabbing)
        }
        .buttonStyle(.bordered)
        .tint(.maeksterAccent)
    }

    // MARK: - Information

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: MaeksterSpacing.s) {
            Text("Information")
                .font(.maeksterShelfTitle)

            VStack(spacing: 0) {
                infoRow("Protocol", release.isTorrent ? "Torrent" : "Usenet")
                if let indexer = release.indexer { infoRow("Indexer", indexer) }
                if let quality = release.qualityName { infoRow("Quality", quality) }
                if let size = release.size { infoRow("Size", LidarrFormat.size(size)) }
                if release.isTorrent {
                    if let seeders = release.seeders { infoRow("Seeders", "\(seeders)") }
                    if let leechers = release.leechers { infoRow("Leechers", "\(leechers)") }
                }
                if let age = release.age { infoRow("Age", LidarrFormat.age(days: age)) }
            }
        }
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.maeksterBody)
                .foregroundStyle(.secondary)
            Spacer(minLength: MaeksterSpacing.m)
            Text(value)
                .font(.maeksterBody)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, MaeksterSpacing.s)
        Divider()
    }

    private func handleDownloadTap() {
        guard release.isRejected else {
            Task { await grab() }
            return
        }
        if overrideAlbumId == nil, pickerArtistId != nil {
            showAlbumPicker = true
        } else {
            showGrabConfirm = true
        }
    }

    private func grab(albumId explicitAlbumId: Int? = nil) async {
        guard let indexerId = release.indexerId else { return }
        isGrabbing = true
        defer { isGrabbing = false }
        do {
            try await client.grabRelease(
                guid: release.guid,
                indexerId: indexerId,
                albumId: explicitAlbumId ?? overrideAlbumId,
                artistId: overrideArtistId
            )
            container?.toastService.showSuccess(String(localized: "Sent to Lidarr"))
            dismiss()
        } catch {
            let detail = (error as? LidarrError).map(LidarrLibraryView.message(for:)) ?? error.localizedDescription
            let message = detail.isEmpty ? String(localized: "Lidarr rejected this release.") : detail
            container?.toastService.showError(message)
        }
    }
}

// MARK: - Album picker

private struct LidarrAlbumPickerSheet: View {
    let artistId: Int
    let client: LidarrClient
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var albums: [LidarrAlbum] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if albums.isEmpty {
                    EmptyStateView(systemImage: "opticaldisc", title: "No Albums", subtitle: "This artist has no albums in Lidarr.")
                } else {
                    albumList
                }
            }
            .navigationTitle("Assign to Album")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .tint(.primary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            albums = (try? await client.albums(artistId: artistId))?
                .sorted { ($0.year ?? "") > ($1.year ?? "") } ?? []
            isLoading = false
        }
    }

    private var albumList: some View {
        List {
            Section {
                ForEach(albums) { album in
                    Button {
                        onSelect(album.id)
                    } label: {
                        HStack(spacing: MaeksterSpacing.m) {
                            LidarrCoverImage(path: album.coverPath, client: client) {
                                RoundedRectangle(cornerRadius: MaeksterCornerRadius.standard)
                                    .fill(Color.secondary.opacity(0.15))
                                    .overlay { Image(systemName: "opticaldisc").foregroundStyle(.secondary) }
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: MaeksterCornerRadius.standard))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(album.title).font(.maeksterCellTitle).lineLimit(1)
                                if let year = album.year {
                                    Text(year).font(.maeksterCaption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Lidarr could not parse this release. Choose the album it belongs to.")
                    .textCase(nil)
                    .font(.maeksterCaption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
