# Rebrand Minidisc → maekster

This app is my fork of Minidisc, and I am renaming it to **maekster** with a new logo. The brand kit is
in `Branding/` at the repo root. Read `Branding/README.md` first: it has the naming rules, the logo
files, the colours and the credits. Treat everything in `Branding/` as read-only source files: copy from it,
never edit it. Also follow the conventions in `CLAUDE.md` (warnings are errors, String Catalogs,
Swift Testing, design-system rules).

Work on a new branch, `rebrand/maekster`. Commit in logical steps. Don't push.

## Naming rules (strict)

- The written name is **maekster**: all lowercase, also at the start of a sentence, in UI text, strings,
  README, docs and metadata. Swift type names use `Maekster…`. Identifiers use `maekster`.
- **mækster** (with æ) exists only inside the logo image files. Never type it as text anywhere.
- The wordmark (the name as a logo) is **not** used inside the iOS app. In the app, use the mark
  (`BrandMark`) and plain text.

## Scope of this pass

Change what users and external services see. **Don't** rename the Xcode project, targets, schemes,
the Swift module, or the internal `Minidisc*` type and token names (`MinidiscColors`,
`MinidiscSpacing`, `minidiscAccent`, `MinidiscRuntime`, …). That rename is a separate pass later.
Also keep internal storage keys and paths that hold user data (for example `app.minidisc.lidarr.*`,
`Documents/app.minidisc/…`, SwiftData store names), so no migration is needed.

## Before you change anything, ask me

1. The new **bundle ID** prefix. `com.nohitdev.minidisc` belongs to the upstream developer. I'll give
   you something like `<my-prefix>.maekster`.
2. The **copyright holder name** for the new COPYRIGHT/NOTICE line.

Then show me a short plan, and go.

## Tasks

### 1. App icon
- Replace the contents of `AppIcon.icon/` with `Branding/xcode/AppIcon.icon/` (solid `#0E0E0E` fill,
  the mark as one layer, translucency off). Remove the old SVG layer.
- I wrote the `icon.json` by hand. Make sure its format matches what Icon Composer and `actool`
  expect (compare it with the current file). If the build rejects the `fill` key, fix it, keep the solid
  near-black fill, and tell me. I'll open the result in Icon Composer to check the Liquid Glass rendering.
- Replace `docs/app-icon.png` with `Branding/logo/png/maekster-app-icon-1024.png`.

### 2. Brand mark asset and onboarding
- Copy `Branding/xcode/BrandMark.imageset` into `Minidisc/Assets.xcassets`. It is a vector SVG with
  original colours (not a template).
- In `OnboardingWelcomeView`, replace `AnimatedMinidiscHero` (the animated Minidisc cartridge) with
  the brand mark: `Image("BrandMark")`, about 220 pt wide, `accessibilityLabel("maekster")`. Keep the
  soft accent glow behind it. Add a calm entrance (fade in with a slight scale). Under Reduce Motion, show it
  still. Delete `MinidiscCartridgeIcon` / `MinidiscCartridgeShell` if nothing else uses them.
- List any other place that draws Minidisc-specific artwork (cartridge, disc) and ask me before you change it.

### 3. Display name and identifiers
- `INFOPLIST_KEY_CFBundleDisplayName` = `maekster` (Debug and Release).
- After I give you the bundle ID: update the app, test and UI-test bundle IDs. Change the URL type
  identifier and the URL scheme from `minidisc` to `maekster`, and update any code that builds or
  parses those URLs. Change the BG task identifier `app.minidisc.wrapped.monthly-update` to
  `<bundle-id>.wrapped.monthly-update`, in `Info.plist` and in code, together.
- Siri: App Shortcut phrases already use `${applicationName}`, so they follow the display name. Because
  "maekster" is hard for Siri to recognise, add `INAlternativeAppNames` to `Info.plist` with the spoken
  form **Mackster**. Check the correct key structure first.
- Check entitlements, keychain access groups and app groups for `nohitdev`/`minidisc` values. Tell me
  what you find; change only what the new bundle ID requires.

### 4. User-facing text
- Replace "Minidisc" with "maekster" in all String Catalogs (`Localizable`, `LocalMusic`, `InfoPlist`,
  `AppShortcuts`) and in every language they contain, in `Info.plist` usage descriptions, and in
  hard-coded UI strings (Wrapped cards and share card, Wrapped cover renderer, Lidarr settings text,
  playback diagnostics title, and so on). Keep each sentence grammatical, with the brand lowercase even
  at the start of a sentence.
- In `AcknowledgementsView`, show maekster first, then credit **Minidisc** (NO HIT Dev,
  github.com/Loriage/Minidisc) and **Cassette** (Mathieu Dubart, github.com/CassetteLab/cassette).

### 5. Names saved on the user's server (careful)
The app creates playlists on the Subsonic server: `"Minidisc Wrapped <year>"`
(`WrappedPlaylistService`) and mood playlists with the prefix `"Minidisc · "` (`Mood.playlistPrefix`).
Existing installs already have these playlists.
- New playlists use `"maekster Wrapped <year>"` and `"maekster · "`.
- The lookup, replace and cleanup logic must also recognise the legacy `Minidisc` names. When it finds
  one, rename or replace it in place, so the user never gets duplicates or orphaned playlists.
- Add Swift Testing tests for the legacy-name handling.

### 6. Names sent to external services
- ListenBrainz `submission_client` and `media_player` → `"maekster"`.
- User-Agent strings (`ExternalArtistImageResolver`, `LRCLIBClient`, and any others) →
  `"maekster/<version> (https://github.com/marcus-gt/Minidisc)"`. Put this in one shared constant.

### 7. README and docs
- README header: use a `<picture>` element with `Branding/logo/svg/maekster-lockup-on-dark.svg` for
  `prefers-color-scheme: dark` and `…-on-light.svg` for light, about 360 px wide, `alt="maekster"`.
  Use no separate H1 title, because the lockup is the title.
- Rewrite the README prose with "maekster" as the app name. Replace "An opinionated fork" with a
  short lineage section: maekster is a fork of Minidisc (NO HIT Dev), which is a fork of Cassette
  (Mathieu Dubart). Keep the feature list, privacy section and badges. The sideload instructions stay.
- Update `docs/*.md` and the prose in `CLAUDE.md` where they mean the app. Leave code identifiers in
  backticks as they are (`MinidiscColors` etc.). In `CLAUDE.md`, add a short "Naming" note with the
  rules above and a pointer to `Branding/README.md`.
- `Branding/logo/png/maekster-github-social-1280x640.png` is for the GitHub social preview. I'll upload
  it by hand. Just remind me at the end.

### 8. Licence and notices
- Leave `LICENSE` (MPL-2.0) unchanged. In `COPYRIGHT` and `NOTICE`, keep every existing line, and add
  a maekster line at the top with the name I give you. Keep the Minidisc and Cassette attributions.
- The Lexend fonts in `Branding/fonts/` are OFL and not bundled in the app. Don't add them to the target.

### 9. Verify
- Build the **Minidisc** scheme with no warnings. Run the **MinidiscTests** scheme.
- Search the repo for `Minidisc`/`minidisc` and sort every remaining hit into three groups:
  (a) internal identifier, kept on purpose; (b) credit or lineage, kept on purpose; (c) missed, which you
  then fix. Show me the (a) and (b) lists.
- Finish with a summary: what changed, decisions I need to make, and how to check the icon in Icon
  Composer and the onboarding screen in the simulator.
