import SwiftUI

// MARK: - Toast view

struct ToastView: View {
    let toast: ToastService.Toast

    var body: some View {
        HStack(spacing: MaeksterSpacing.s) {
            leading

            VStack(alignment: .leading, spacing: 1) {
                Text(LocalizedStringKey(toast.message))
                    .font(.maeksterCellTitle)
                    .lineLimit(4)
                if let subtitle = toast.subtitle {
                    Text(subtitle)
                        .font(.maeksterCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .multilineTextAlignment(.leading)

            if case .undoQueueRemoval = toast.action {
                Text("Undo").font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.maeksterAccent)
                    .padding(.leading, MaeksterSpacing.s)
            } else if toast.action != nil {
                Image(systemName: "chevron.forward")
                    .font(.maeksterCaption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, MaeksterSpacing.s)
            }
        }
        .padding(.horizontal, MaeksterSpacing.m)
        .padding(.vertical, MaeksterSpacing.s)
        .background(
            RoundedRectangle(cornerRadius: MaeksterCornerRadius.large)
                .fill(.regularMaterial)
        )
        .padding(.horizontal, MaeksterSpacing.l)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    @ViewBuilder
    private var leading: some View {
        if let coverArtId = toast.coverArtId {
            CoverArtView(id: coverArtId, size: 120)
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: MaeksterCornerRadius.standard))
        } else {
            Image(systemName: toast.style.systemImage)
                .foregroundStyle(toast.style.tint)
        }
    }
}

// MARK: - Overlay modifier

struct ToastOverlay: ViewModifier {
    var reservesMiniPlayerSpace = true
    @Environment(ToastService.self) private var toastService
    @Environment(\.appContainer) private var container
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hostID = UUID()

    private var miniPlayerVisible: Bool {
        container?.playerState.currentTrack != nil || container?.playerState.isLiveStream == true
    }

    private var bottomInset: CGFloat {
        reservesMiniPlayerSpace && miniPlayerVisible ? MaeksterSpacing.miniPlayerBottomMargin + MaeksterSpacing.s : MaeksterSpacing.l
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast = toastService.current, toastService.isActiveOverlay(hostID) {
                    toastContent(toast)
                        .padding(.bottom, bottomInset)
                        .id(toast.id)
                }
            }
            .onAppear { toastService.overlayDidAppear(hostID) }
            .onDisappear { toastService.overlayDidDisappear(hostID) }
            .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: toastService.current)
    }

    @ViewBuilder
    private func toastContent(_ toast: ToastService.Toast) -> some View {
        if toast.action != nil {
            Button { handleTap(toast) } label: {
                ToastView(toast: toast).frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(undoIdentifier(toast))
        } else {
            ToastView(toast: toast).allowsHitTesting(false)
        }
    }

    private func undoIdentifier(_ toast: ToastService.Toast) -> String {
        if case .undoQueueRemoval = toast.action { return "toast.undoQueue" }
        return "toast.action"
    }

    private func handleTap(_ toast: ToastService.Toast) {
        guard let action = toast.action else { return }
        toastService.dismiss()
        switch action {
        case .undoQueueRemoval(let removal):
            Task {
                if await container?.playerService.restoreQueueTrack(removal) == true {
                    toastService.showConfirmation(String(localized: "Restored to queue"), coverArtId: removal.song.coverArtId)
                } else {
                    toastService.show(String(localized: "The queue has changed. This removal can no longer be undone."))
                }
            }
        case .navigateToDownloads:
            NotificationCenter.default.post(name: .maeksterNavigateToDownloads, object: nil)
        case let .navigateToPlaylist(id, name, coverArtId):
            postNavigateToPlaylist(playlistId: id, name: name, coverArtId: coverArtId)
        }
    }
}

extension View {
    func toastOverlay(reservesMiniPlayerSpace: Bool = true) -> some View {
        modifier(ToastOverlay(reservesMiniPlayerSpace: reservesMiniPlayerSpace))
    }
}
