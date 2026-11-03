import AppIntents

struct MaeksterShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PlayMaeksterMusicIntent(), phrases: [
            "Play \(\.$music) in \(.applicationName)",
            "Play music in \(.applicationName)"
        ], shortTitle: "Play Music", systemImageName: "play.fill")
        AppShortcut(intent: PlayMaeksterMoodIntent(), phrases: [
            "Play \(\.$mood) mood in \(.applicationName)",
            "Play a mood in \(.applicationName)"
        ], shortTitle: "Play a Mood", systemImageName: "moon.stars")
        AppShortcut(intent: MaeksterSmartShuffleIntent(), phrases: [
            "Smart Shuffle in \(.applicationName)"
        ], shortTitle: "Smart Shuffle", systemImageName: "shuffle")
        AppShortcut(intent: ResumeMaeksterIntent(), phrases: [
            "Resume playback in \(.applicationName)"
        ], shortTitle: "Resume Playback", systemImageName: "play.circle")
        AppShortcut(intent: PauseMaeksterIntent(), phrases: [
            "Pause playback in \(.applicationName)"
        ], shortTitle: "Pause Playback", systemImageName: "pause.circle")
        AppShortcut(intent: NextMaeksterTrackIntent(), phrases: [
            "Next track in \(.applicationName)"
        ], shortTitle: "Next Track", systemImageName: "forward.end")
        AppShortcut(intent: PreviousMaeksterTrackIntent(), phrases: [
            "Previous track in \(.applicationName)"
        ], shortTitle: "Previous Track", systemImageName: "backward.end")
    }
}
