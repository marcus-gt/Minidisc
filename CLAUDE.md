# CLAUDE.md

maekster is an iPhone music player for Subsonic / OpenSubsonic servers (Navidrome first). It also plays
local folders the user references through Files, and integrates with ListenBrainz, Lidarr, AudioMuse-AI,
LRCLIB lyrics, Siri / App Intents and a yearly "Wrapped" recap. A native macOS app is being built from
the same target (plan and steps in #100).

## Naming

The app is **maekster**, a fork of Minidisc (NO HIT Dev), which is a fork of Cassette (Mathieu Dubart).
The brand kit and full rules are in `Branding/README.md`; treat `Branding/` as read-only.

- Write **maekster** in all lowercase, also at the start of a sentence: UI text, strings in every language,
  README, docs, metadata, commit messages. Swift type names use `Maekster…` (e.g. `MaeksterBrand`);
  identifiers, keys and bundle-ID segments use `maekster`.
- **Exception: the system app name is mækster** (with æ), decided after `Branding/README.md` was written,
  and it overrides the guide there. It applies to `INFOPLIST_KEY_CFBundleDisplayName`, `CFBundleName` /
  `CFBundleDisplayName` in `InfoPlist.xcstrings`, and the permission texts (`NS*UsageDescription` in the
  build settings, `Info.plist` and `InfoPlist.xcstrings`, every language), so permission dialogs match
  their title. Everything else, including in-app sentences, stays **maekster**. The Siri synonym
  `INAlternativeAppNames` stays "Mackster".
- In the app, use the mark (`Image("BrandMark")`) and plain text. Never use the wordmark.
- Names sent to external services come from `MaeksterBrand` (`Utilities/MaeksterBrand.swift`).
- Types, tokens, modifiers, notifications, logger subsystems and stored names (`maekster.*` /
  `app.maekster.*` defaults, the `app.maekster.server-credentials` Keychain service,
  `Documents/app.maekster/…`, `maekster-*` stores) use maekster (#46). `StorageMigration` moved
  data saved under the old `minidisc` names once, at launch; it is the only code that still names
  them.
- The project is `maekster.xcodeproj`. Targets, schemes, the Swift module and the source folders use
  `Maekster` (`Maekster`, `MaeksterTests`, `MaeksterUITests`), because Swift identifiers can't contain
  æ and module names are capitalised.
- Only credits and `Branding/` still say Minidisc: Minidisc (NO HIT Dev) and Cassette are named in the
  README, NOTICE, COPYRIGHT, acknowledgements and `MaeksterURLs.minidisc`.
- Earlier versions created server playlists named `maekster Wrapped <year>` / `maekster · <Mood>`.
  Nothing creates them now. Match them through `WrappedPlaylistService.year(fromPlaylistName:)` and
  `Mood.isPlaylistName(_:)`, not by comparing strings.

## Toolchain facts that shape the code

| Setting | Value | Consequence |
|---|---|---|
| Platform | iOS 26.1+, iPhone only (`TARGETED_DEVICE_FAMILY = 1`), portrait; **macOS 26.1+**, native SwiftUI (not Catalyst), from the same `Maekster` target | No iPad layout. Shared code compiles for both; the iPhone UI (`Views/`) is iOS-only and the Mac UI (`MacViews/`) macOS-only (see "macOS" below) |
| Swift | 6.0, `SWIFT_STRICT_CONCURRENCY = complete`, approachable concurrency | All concurrency diagnostics are on |
| `SWIFT_DEFAULT_ACTOR_ISOLATION` | **MainActor** | Every type is MainActor unless it says otherwise. Value types and helpers used from service actors **must be declared `nonisolated`** (`nonisolated struct …`, `nonisolated enum …`, `nonisolated static let` on `Logger`) |
| `SWIFT_TREAT_WARNINGS_AS_ERRORS` | YES | A warning fails the build. Don't leave unused vars or `try?` results that trigger warnings |
| `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY` | YES | Import the module you use in each file (e.g. `import SwiftSonic`, `import OSLog`) |
| Strings | String Catalogs, `STRING_CATALOG_GENERATE_SYMBOLS = YES` | Catalogs: `Localizable`, `LocalMusic` (table), `InfoPlist`, `AppShortcuts` |
| Dependency | `SwiftSonic` remote Swift package (`github.com/MathieuDubart/swiftsonic`) | The Subsonic API client. It is a separate MIT project with its own README/CHANGELOG/tests; change it only on purpose, upstream |

## Build and test

Inside Xcode, use the xcode-tools MCP commands. They are faster and pick up the active scheme:

- Build: `BuildProject` (scheme **Maekster**)
- Quick type check of one file: `XcodeRefreshCodeIssuesInFile`
- Unit tests: the **Maekster** scheme has no test action; run tests through the `MaeksterTests` scheme

From the command line (the project is `maekster.xcodeproj` at the repo root; there is no workspace):

```sh
# Build
xcodebuild build -project maekster.xcodeproj -scheme Maekster \
  -destination 'platform=iOS Simulator,name=<any iPhone simulator>'

# Build the Mac app (unsigned is enough to check it compiles)
xcodebuild build -project maekster.xcodeproj -scheme Maekster \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

# Unit tests (MaeksterTests, Swift Testing)
xcodebuild test -project maekster.xcodeproj -scheme MaeksterTests \
  -destination 'platform=iOS Simulator,name=<any iPhone simulator>' \
  -only-testing:MaeksterTests

# One suite or test
  -only-testing:MaeksterTests/ServerServiceTests
  -only-testing:MaeksterTests/ServerServiceTests/addServer_firstServer_becomesActive()

```

Shared schemes: `Maekster`, `MaeksterTests`, `MaeksterUITests`.

### UX verification (opt-in UI tests)

`MaeksterUITests/MaeksterUXVerificationTests` drives the real app against a local fake Subsonic server,
`Scripts/Testing/ux-fixture-server.py` (loopback port 18992). It needs a dedicated simulator named
**maekster UX Verification**. The tests skip any other device. Follow `Scripts/Testing/README.md`
exactly; it covers ad-hoc signing (needed for Keychain), the per-scenario catalogue modes and the
`rtk proxy` command prefix. Don't point that simulator at a real server.

## Folder map

```
maekster.xcodeproj
Maekster/                      app target sources
  App/                         @main app, AppContainer (composition root), MaeksterRuntime, notification names
  AppIntents/                  App Intents / Siri / Shortcuts (AudioPlaybackIntent, MusicEntity)
  DesignSystem/                tokens (colors, spacing, typography), Components/, Theming/, Platform/ wrappers
                               README.md, MaeksterColors.md, Platform/CONVENTIONS.md: read before UI work
  Keychain/                    KeychainService + ServerCredentials (password, custom headers, AudioMuse token)
  Models/
    Domain/                    app value types: DisplayableSong, MaeksterError, UserFacingError, sorts, etc.
    Persistence/               SwiftData @Model types (ServerConfig, DownloadedTrack, CachedTrack, LibraryIndexModels…)
    Navigation/ Integrations/ ListenBrainz/ Recommendations/ Wrapped/
  ObservableState/             @Observable @MainActor state + settings (PlayerState, ServerState, *Settings)
  Services/
    Protocols/                 service contracts (PlayerServiceProtocol, LibraryServiceProtocol, …)
    Implementations/           most concrete services (PlayerService, ServerService, LibraryService,
                               MediaResolver, DownloadService, NowPlayingService, PlaylistService, …)
    Audio/                     AudioEngine protocol, AVPlayerEngine (dual-deck), gapless/crossfade planning
    LibraryIndex/              local-first catalogue: LibraryCatalog, LibraryIndexStore/Synchronizer, RemoteSource
    Networking/                ServerConnection, CustomHeadersTransport, background download transport
    Offline/                   offline browsing reader/library + removal planner
    Favorites/                 offline favourites store + automatic sync
    LocalMusic/                security-scoped local folder library
    Cache/ Diagnostics/ Intents/ Lidarr/ ListenBrainz/ Lyrics/ Recommendations/ Integrations/ Persistence/
  ViewModels/                  @Observable @MainActor screen view models
  Views/                       iPhone screens (iOS-only): Main/ (tabs, player, home, search), Browse/,
                               Discover/, Settings/, Onboarding/, LocalMusic/, Lidarr/, Wrapped/
  SharedViews/                 screens used by both apps (both platforms): Settings/ pages, LocalMusic/
                               folder management, Discover/ cards and pages, the download activity section
  MacViews/                    Mac screens (macOS-only): MacRootView (the Mac `RootView`), MacSignInView,
                               MacMainView (sidebar, `MacRoute`s), MacHomeView, MacDiscoverView, MacShelf (cover
                               shelves), library lists, album/artist/genre pages, MacPlaylists,
                               MacSongList (album and playlist songs), MacTrackTable (Songs library) + MacSongMenu, MacPlayerBar
  Utilities/                   Logger categories, formatting, HeaderValidator, PlatformImage, haptics
  *.xcstrings, Info.plist, Maekster.entitlements, PrivacyInfo.xcprivacy, AppIntentVocabulary.plist
MaeksterTests/                 ~110 Swift Testing files (no XCTest)
MaeksterUITests/               XCTest UI tests incl. MaeksterUXVerificationTests
Scripts/Testing/               UX fixture server + instructions
```

## Architecture

### Composition root

There is no DI framework. `AppContainer` (`App/AppContainer.swift`) is a `@MainActor` class that
builds the entire service graph in one `init`, in dependency order, and owns long-lived lifecycle tasks.

- `MaeksterRuntime.shared` builds the container exactly once. **UI and headless App Intents share it**,
  so there is one player and one engine. It is registered with `AppDependencyManager`, and intents get it
  through `@Dependency private var runtime: MaeksterRuntime`.
- `MaeksterApp.makeContainer` runs the boot sequence. Order matters:
  `setup()` (wires PlayerService ↔ NowPlayingService) → `serverService.loadPersistedState()` →
  `networkMonitor.start` → `nowPlayingService.start()` → cache invalidation and migrations →
  `playerService.restoreSession()` → background sync and BGTask scheduling.
- The UI gets the container through `@Environment(\.appContainer)` (optional, `AppContainer?`). A few
  hot objects are also injected directly: `ArtworkImageCache`, `DominantColorExtractor`, `ToastService`,
  and the main `ModelContainer`.
- Views build their view models lazily, passing in only the services they need from the container:
  ```swift
  viewModel = AlbumDetailViewModel(albumId: albumId, libraryService: c.libraryService,
                                   downloadService: c.downloadService, toastService: c.toastService,
                                   serverState: c.serverState)
  ```
  View models depend on **narrow protocols** where they can (`any AlbumBrowsing`, not the whole
  `LibraryServiceProtocol`).

### Concurrency model

- **Services are `actor`s** (`PlayerService`, `ServerService`, `LibraryService`, `MediaResolver`,
  `NowPlayingService`, `DownloadService`, `LibraryCatalog`, `PlaybackSessionService`, …).
- **UI state is `@Observable @MainActor final class`** in `ObservableState/` (`PlayerState`,
  `ServerState`, settings) and `ViewModels/`. A service exposes its state as `nonisolated let state` and
  mutates it with `await MainActor.run { state.x = … }`.
- **Generation counters guard against stale async results.** This is the main defensive pattern in the
  codebase. `PlayerService` keeps `playbackGeneration`, `transportIntentGeneration`, `queueGeneration`,
  `prefetchGeneration` and others, and checks `isCurrentPlaybackIntent(...)` after every `await`. The
  server layer uses `ServerConnection.Version` (serverID + revision): long-lived clients cache on it, and
  reads re-check `activeConnectionVersion()` after awaiting so a server switch can't leak results.
  Engine callbacks carry an `AudioEnginePlaybackToken`. New async code in these areas must follow the
  same pattern.
- Cancellation is handled explicitly: `catch is CancellationError { throw CancellationError() }`,
  `try Task.checkCancellation()`, bounded `TaskGroup`s (typically 5 in flight).
- No Combine in new code. `NotificationCenter` is used for cross-screen events (names in
  `App/MaeksterNotifications.swift`, e.g. `.maeksterFavoritesChanged`, `.maeksterOfflineLibraryChanged`,
  `.maeksterNavigateToAlbum`). Post them from the main actor.

### Server layer

```
ServerState (@Observable)  ◀── ServerService (actor) ──▶ SwiftData ServerConfig + Keychain ServerCredentials
                                   │
                                   └─ activeConnection() → ServerConnection (process-local snapshot)
                                                            └─ makeSwiftSonicClient() → SwiftSonicClient
                                                               (CustomHeadersTransport adds proxy headers)
```

- `ServerService` owns server CRUD, the active server and connection testing (mapped to
  `ConnectionTestError`). Every activation or credential edit bumps the revision through
  `publishConnectionChange`, which then sets `ServerState.activeConnectionVersion`.
- Writes go to the Keychain first, then SwiftData, with rollback if the second step fails. Keep that
  ordering.
- `ServerConnection` contains secrets. Its `description` is redacted, and
  `authorizationHeaders(for:)` returns custom headers **only for the server's own origin**, so reverse
  proxy credentials never reach radio or artwork hosts. Always use it for any URL handed to AVPlayer or
  URLSession.
- `NavidromeCompatibility` runs on activation to detect Navidrome upgrades that change resource IDs,
  before any cache reads IDs.
- Online state: `NetworkMonitor` (NWPathMonitor) reduces path updates into a monotonic
  `NetworkPathEvent`, applies it to `ServerState`, and calls `playerService.handleNetworkPathChanged`
  directly. `ServerState.isOnline` is `network && !isOfflineModeEnabled`. Generation 0 is the launch
  baseline and recovery code ignores it.

### Library layer

```
ViewModels ─▶ LibraryService (actor, LibraryServiceProtocol = many small protocols)
                 ├─ LibraryCatalog (local-first) ─▶ LibraryIndexStore (separate SwiftData store)
                 │                                 └▶ LibraryIndexSynchronizer ─▶ SwiftSonicLibrarySource ─▶ ServerService
                 ├─ direct SwiftSonic calls (star, similar songs, artist info, scrobble) via a cached client
                 ├─ OfflineFavoritesStore / OfflineBrowsingReader fallbacks when offline or unreachable
                 └─ DownloadService, StatsService
```

- `LibraryServiceProtocol` combines narrow protocols (`AlbumBrowsing`, `ArtistBrowsing`,
  `PlaylistBrowsing`, `PlaybackQueueBuilding`, `PlaybackReporting`, …). Depend on the narrowest one.
- `LibraryCatalog` answers browse and search from the persisted index once a scan is complete, and only
  goes to the network otherwise. Automatic full index walks run only on an unmetered, unconstrained path
  (`ServerState.libraryIndexPreparationSnapshot`). Pull-to-refresh works on any online path.
- The library index lives in its own `ModelContainer` (`maekster-library-index`, versioned schema and
  migration plan `LibraryIndexSchemaV3` / `LibraryIndexMigrationPlan`). It is a discardable cache, kept
  apart from user data. The playback session is also in its own store (`maekster-session`) so frequent
  position saves stay out of the main observation graph. The main store schema is in
  `ModelContainer.maekster`.
- Offline fallbacks only happen for network-class errors (`UserFacingError.noNetwork`,
  `.serverUnreachable`, `.contentUnavailableOffline`), never on cancellation.

### Player layer

```
UI / Intents / Remote commands
      │
      ▼
PlayerService (actor, ~4.7k lines: queue, shuffle/repeat, auto-extend, smart shuffle, instant mix,
      │        radio, session restore, network and audio-session recovery, crossfade/gapless prefetch,
      │        ReplayGain, scrobbling, stats)
      ├─▶ MediaResolver ── download ▶ stream cache ▶ remote stream (via ServerConnection)
      │                    (local folder files resolve through LocalMusicStore instead)
      ├─▶ AudioEngine protocol ◀─ AVPlayerEngine (dual-deck; delegate callbacks through AudioEngineBridge)
      ├─▶ PlayerState (@MainActor, read by the UI)
      ├─▶ NowPlayingService ─▶ NowPlayingCenterPresenter (MPNowPlayingInfoCenter / remote commands)
      ├─▶ PlaybackSessionService (queue + position persistence)
      └─▶ LibraryService (queue building, scrobble), ListenBrainzService, StatsService, DownloadService/cache
```

- **PlayerService never talks to SwiftSonic for media URLs.** It always goes through `MediaResolver`.
  `MediaResolver.availability` only reports `.missing` on a structured Subsonic `getSong` not-found
  response. Anything else is `.unknown`.
- `PlayerState` represents **user intent** (`playbackState`, queue, index), not the physical engine
  state. `PlayerService` tracks the engine separately (`activeEngineState`). `waitingReason` is
  presentation-only.
- The engine is synchronous and internally locked. Callbacks arrive on its own thread and are tagged
  with a playback token. A callback whose token isn't current is ignored.
- `MediaSource` cases: `.localFile`, `.downloaded`, `.cached`, `.stream(url, customHeaders:)`,
  `.liveStream`.
- Session persistence: positions are saved on a timer, on `scenePhase == .inactive`, and in full on
  `.background` (skipped while radio is playing).
- Settings changes are pushed into the actor explicitly: `replayGainSettingsDidChange()`,
  `crossfadeSettingsDidChange()`.

### Other subsystems

- **Downloads**: `DownloadService` (actor) with `BackgroundDownloadTransport` (a background URLSession)
  and `DownloadQueueController`. It publishes `progressStream`, which AppContainer mirrors into
  `DownloadActivityState`. Files live under `Documents/app.maekster/downloads`.
- **Artwork**: `ArtworkImageCache` (thumb/hero tiers, `@thumb` / `@hero` filename suffixes). The cache
  version in `AppContainer.currentCoverArtCacheVersion` must be bumped when the tiering changes.
- **Radios**: Wrapped years/months and moods play as radios, not server playlists. `RadioQueue` queues
  the first picks, refills from the rest and then continues with Instant Mix around seed tracks.
  Nothing runs in the background any more (no BGTask).
- **Migrations** are one-shot, keyed by UserDefaults flags (`maekster.*_vN`) in `AppContainer`
  extensions. Add a new flag; don't reuse an old one.

## Conventions

**Swift / concurrency**
- New services: an `actor` behind a protocol in `Services/Protocols/` when views or tests need to
  substitute it; add it to `AppContainer.init` in dependency order.
- New observable state or view models: `@Observable @MainActor final class`. Views keep the view model
  in `@State private var viewModel: XViewModel?` and create it from `container`.
- Data crossing actors must be `Sendable`, and value types must be declared `nonisolated` (see the
  default-isolation note above).
- Re-validate generation / connection version after every `await` that can race with a user action or
  a server switch.
- Errors: throw `MaeksterError` internally and map to `UserFacingError.from(error)` for display. Don't
  surface raw `localizedDescription`.

**Logging and privacy**
- Use the `Logger` categories in `Utilities/Logger+Maekster.swift` (`Logger.player`, `.library`,
  `.server`, …). Add a new `nonisolated static let` there instead of creating ad-hoc loggers.
- Song/album IDs are logged `privacy: .public`. URLs, hosts and credentials are `.private` or omitted.
  Never log `ServerCredentials`, custom header values or full stream URLs. Diagnostics
  (`PlaybackDiagnostics`, `AudioEngineFailure`) store only domain/code pairs, never `userInfo`.
- Bracketed tags are used in log messages, e.g. `[TRANSITION]`, `[CLIENT]`, `[ExtMigration]`.

**UI / design system** (details in `Maekster/DesignSystem/README.md` and `MaeksterColors.md`)
- No magic numbers: `MaeksterSpacing`, `MaeksterCornerRadius`, `.maekster*` fonts from
  `MaeksterTypography`.
- Colors: semantic SwiftUI colors for text and backgrounds. `maeksterAccent` is for primary interactive
  elements only. New colors go into `Assets.xcassets` plus `MaeksterColors.md`.
- Plain SF Pro only (no `design: .rounded`) outside Wrapped and the generated-cover renderers. Favourites
  are hearts. Player, album, artist and local-collection pages are always dark (`ArtworkSurfacePalette`).
- Round buttons on those screens use `.buttonStyle(.maeksterCircle(...))` with `MaeksterControlSize`.
  Track rows have no "…" button; row actions live in the context menu and swipe actions.
- Design direction, decisions and deferred items: `docs/DesignOverhaul.md`.
- Cover art goes through `CoverArtCard` (or `CoverArtView` + `.maeksterCoverStyle` in flexible grids).
  Use `EmptyStateView` instead of `ContentUnavailableView` in screens. Reuse `SongRow`, `AlbumRow`,
  `PlayButton` and `SectionHeader`.
- Platform-specific APIs go behind `maekster`-prefixed modifiers in `DesignSystem/Platform/` (see
  `CONVENTIONS.md`). Keep `#if os(...)` out of view bodies.

**macOS** (#100)
- One target, two platforms: macOS is a supported destination of `Maekster`, with its own sandbox
  entitlements (`Maekster-macOS.entitlements`). Shared code (models, services, state, view models,
  design system) compiles for both. Use `PlatformImage` / `PlatformColor` and the `DesignSystem/Platform/`
  wrappers instead of UIKit/AppKit types; put small platform differences in `#if os(iOS)` /
  `#if os(macOS)` inside services and utilities, not in view bodies.
- Synchronised folders can't limit a folder to one platform, so **each file** under `Views/` is
  iOS-only and each file under `MacViews/` macOS-only (File inspector → Target Membership → platform,
  stored as `platformFiltersByRelativePath` in the project). A new view file needs that filter.
  `Scripts/doctor.sh` fails when one is missing. Xcode writes these entries on one line
  (`MacViews/X.swift = (macos, );`) and reformats the whole list when it saves the project; that's
  harmless, and doctor accepts both that and the three-line form. A few shared components that still open iPhone
  sheets are iOS-only too, until the Mac needs them.
- The Mac `RootView` (in `MacViews/`) takes the iOS one's name so `MaeksterApp` needs no `#if`.
  A screen both apps use goes in `SharedViews/` (shared components stay in `DesignSystem/Components/`);
  use the `maekster*` text-input and title wrappers instead of iOS-only modifiers there.
  Pages open other pages through `MacNavigator` (in the environment). Mac screens reuse the iPhone view
  models and shared components (`ServerFormView`, `AlbumGridCell`,
  `CoverArtCard`, …) and the iPhone app's existing strings where the wording fits.
- iOS-only behaviour: the audio session (`SystemAudioSessionController` does nothing on macOS, and
  route/interruption handling is compiled out), SiriKit media intents and the Siri audio entities
  (macOS 27+ API), the background-download app delegate, haptics.
- The Mac uses the data protection keychain (`kSecUseDataProtectionKeychain` in `KeychainService`, plus
  `keychain-access-groups` in the Mac entitlements), like iOS. It shares the default access group with the
  iPhone build, so credentials saved by the iPhone app running on a Mac ("Designed for iPhone", same
  bundle ID and container) stay readable.
- Local music folders: the sandboxed Mac keeps folder access only through security-scoped, read-only
  bookmarks (`LocalMusicBookmark`); iOS uses minimal bookmarks.
- Unit tests stay iOS-only. Check the Mac side with the macOS build above.
- User-facing strings are localized through the String Catalogs (`LocalizedStringResource` /
  `String(localized:)`; local-music strings use `table: "LocalMusic"`). Don't hard-code English in
  services that produce UI text.
- The DesignSystem README mentions an "MPL-2.0 header" for new components. No source file has one, so
  don't add it.

**Tests** (`MaeksterTests`)
- Use Swift Testing only: `import Testing`, `@testable import Maekster`, `@Suite("Name") @MainActor struct …`,
  `@Test func subject_condition_expectation()`, `#expect`, `await #expect(throws:)`.
- Swift Testing runs tests in parallel, so each test creates its **own** in-memory stores:
  `ModelContainer.maekster(inMemory: true)` (also `.libraryIndex` / `.session`), or
  `AppContainer(inMemory: true, userDefaults: <isolated suite>)`. Never share containers or
  `UserDefaults.standard` between tests.
- Fakes are hand-written next to the suite that first needs them (e.g. `MockKeychain` and
  `MockAudioStreamCache` in `ServerServiceTests.swift`, `MockServerService` in
  `OnboardingViewModelTests.swift`). Reuse an existing one before writing another. HTTP is stubbed at
  the SwiftSonic `HTTPTransport` level (`StubHTTPTransport`).
- Timing-sensitive player code takes injectable timing structs (`PlaybackNetworkRecoveryTiming`,
  `PlaybackAudioRecoveryTiming`) and an injectable `AudioEngine` / `AudioSessionControlling`. Use them
  in tests rather than sleeping.

**Git**
- Conventional-style commit subjects: `feat: …`, `fix: …`.
