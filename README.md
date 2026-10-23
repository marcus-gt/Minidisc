<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Branding/logo/svg/maekster-lockup-on-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="Branding/logo/svg/maekster-lockup-on-light.svg">
    <img src="Branding/logo/svg/maekster-lockup-on-light.svg" alt="maekster" width="360">
  </picture>
</p>

<p align="center">
  maekster is an opinionated music player for iOS that plays the music from your own server, and it gives you an experience that is close to Apple Music.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MPL--2.0-brightgreen.svg" alt="License: MPL 2.0"></a>
  <a href="#requirements"><img src="https://img.shields.io/badge/platform-iOS%2026%2B-blue.svg" alt="Platform: iOS 26+"></a>
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6-orange.svg" alt="Swift 6"></a>
</p>

## Screenshots

|                        Home                        |                        Discover                        |                        Player                        |                        Album                        |                           Lidarr                           |
| :------------------------------------------------: | :----------------------------------------------------: | :--------------------------------------------------: | :-------------------------------------------------: | :--------------------------------------------------------: |
| <img src="docs/screenshots/home.jpeg" width="150"> | <img src="docs/screenshots/discover.jpeg" width="150"> | <img src="docs/screenshots/player.jpeg" width="150"> | <img src="docs/screenshots/album.jpeg" width="150"> | <img src="docs/screenshots/lidarr-album.jpeg" width="150"> |

## What is maekster?

maekster is a music player for iOS, written in Swift and SwiftUI, that plays the music from your own server. It uses the Subsonic and OpenSubsonic API, so it works with [Navidrome](https://www.navidrome.org) and with other servers that follow these standards.

maekster does not use accounts or subscriptions, and it does not track you, so your music stays between your device and your server. It gives you the same smooth experience as Apple Music, but it plays the music that you own.

## Lineage

maekster is a fork of [Minidisc](https://github.com/Loriage/Minidisc) by NO HIT Dev, which is itself a fork of [Cassette](https://github.com/CassetteLab/cassette) by Mathieu Dubart. It keeps Minidisc's approach: iOS only, few settings with good defaults, and the usual iOS patterns. If you want a client for both Mac and iPhone, use Cassette.

## Features

**A player that is close to Apple Music**

- Native iOS 26 design with Liquid Glass.
- A full-screen player with a large cover.
- A mini-player that stays in the tab bar, and you tap it to open the full player.
- A Home screen with your top picks, your recent music, and one shelf for each genre.
- Background playback with lock screen and Control Center controls.
- AirPlay support.

**Your library**

- Browse your playlists, artists, albums, downloads, and favorites.
- Search all of your library.
- Offline mode, so you can download albums, playlists, or single tracks.
- Sync your favorites with the server.
- Lyrics, shuffle, repeat, and a full queue.
- The app keeps your session and continues from the last position.

**More functions**

- **Wrapped** gives you a summary of your year of listening.
- **ListenBrainz** scrobbles your plays and gets recommendations for you.
- **AudioMuse-AI** builds weekly mood playlists from the sound of your music.
- **Lidarr** manages your music collection from the app: add artists, monitor and search for missing albums, pick releases with an interactive search, and follow the download queue with manual import.
- **Streaming quality** is lossless by default, but you can pick a lighter format per network (Wi-Fi and cellular).

**Privacy**

- maekster does not track you. Library and playback traffic goes directly to your configured server.
- If you select LRCLIB as the lyrics source, or use it as the automatic fallback, maekster sends the track title, artist, album, and duration to LRCLIB over HTTPS. Server credentials, custom headers, and server identifiers are never included.
- maekster keeps your credentials only in the iOS Keychain.
- maekster can send custom HTTP headers for a server behind a reverse proxy, for example Cloudflare Access or Authelia.

## Installation

### iOS: sideload the app

1. Download the `.ipa` file from the [Releases](../../releases) page.
2. Install the file with AltStore, Sideloadly, or a different sideload tool. The tool signs the app with your Apple ID during the installation.

### Build from the source

You need these items:

- macOS 15 or later, with Xcode 26 or later.
- A Subsonic, OpenSubsonic, or Navidrome server.
- An Apple Developer account. The free level is sufficient for a personal build.

Do these steps:

1. Clone the repository and open the project.
    ```bash
    git clone https://github.com/marcus-gt/Minidisc.git
    cd Minidisc
    open Minidisc.xcodeproj
    ```
    Swift Package Manager gets the dependencies (SwiftSonic), so you do not have to do more setup.
2. Select your team in **Signing & Capabilities**.
3. Select an iOS 26 device or simulator.
4. Build and run the app when you press Command-R.
5. At the first start, maekster asks for your server address, your username, and your password. Enter them and tap **Connect**. If your server is behind a reverse proxy that needs custom headers, open **Advanced** and add the headers.

## Requirements

- iOS 26.1 or later.
- A Subsonic, OpenSubsonic, or Navidrome server.

## Server compatibility

maekster works with each server that has the Subsonic or OpenSubsonic API. Navidrome is the recommended server, and maekster is tested primarily with Navidrome. If your server has the Subsonic API but a function does not work, [open an issue](https://github.com/marcus-gt/Minidisc/issues).

## Architecture

This information is for developers:

- **UI.** SwiftUI views with `@Observable @MainActor` view models, and the views have no business logic.
- **Services.** Swift actors, for example `PlayerService` and `LibraryService`, that do not import SwiftUI or UIKit.
- **Playback.** A two-deck `AVPlayer` engine (`AVPlayerEngine`) for gapless playback, real crossfades, and ReplayGain, which connects to `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`.
- **Subsonic API.** [SwiftSonic](https://github.com/CassetteLab/swiftsonic) does all server communication.
- **Integrations.** ListenBrainz, AudioMuse-AI, and Lidarr each have their own client and settings.
- **Persistence.** SwiftData for the app data, and Keychain for the credentials.
- **Concurrency.** Swift 6 strict concurrency.
- **Dependencies.** SwiftSonic, and there are no other dependencies.

## License

maekster uses the [MPL-2.0](LICENSE) license.

- You can use, study, change, and share the source.
- Changed files stay under MPL-2.0, but you can combine them with proprietary code in a larger work.

Dependencies: [SwiftSonic](https://github.com/CassetteLab/swiftsonic) (MIT), which is compatible with MPL-2.0.

> Code before commit 21f9227 used the GPL-3.0-or-later license.

## Acknowledgments

- [Minidisc](https://github.com/Loriage/Minidisc) by NO HIT Dev, because maekster is a fork of Minidisc.
- [Cassette](https://github.com/CassetteLab/cassette) by Mathieu Dubart, because Minidisc is a fork of Cassette.
- The [Navidrome](https://www.navidrome.org) team, because Navidrome is an excellent self-hosted music server.
- The [OpenSubsonic](https://opensubsonic.netlify.app) community, because they modernized the Subsonic API.

