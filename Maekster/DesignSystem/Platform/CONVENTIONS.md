# Platform Wrappers

This folder contains SwiftUI modifiers and types that bridge platform-specific
APIs (iOS/macOS) into a unified maekster API. The goal is to keep `#if` directives
out of view bodies and service layer.

## Conventions

- Each file scopes a single concern (list styles, navigation transitions, etc.)
- Public modifiers are prefixed with `maekster` (e.g. `maeksterSheetListStyle`)
- Wrappers MUST become no-op (or sensible default) on the unsupported platform,
  never crash, never throw a precondition failure
- iOS-only or macOS-only types are wrapped in `#if os(...)`. Public-facing types
  (parameters, enums) must compile on both platforms — define cross-platform
  enums and translate internally where needed

## Adding a new wrapper

1. Identify the iOS-only or macOS-only API
2. Determine the sensible behavior on the unsupported platform (no-op, fallback, etc.)
3. Create the wrapper as an extension on `View` (or appropriate type)
4. Use the `maekster` prefix
5. Document why the wrapper exists in a doc comment

## Files

- `NavigationTitle+Maekster.swift` — `navigationBarTitleDisplayModeInline/Large()` wrappers (no-op on macOS)
- `ListStyles+Maekster.swift` — `maeksterSheetListStyle()` (inset grouped on iOS, inset on macOS)
- `NavigationTransitions+Maekster.swift` — `maeksterZoomTransition()` (zoom transition on iOS, no-op on macOS)
- `FullScreenCover+Maekster.swift` — `maeksterFullScreenCover()` (a sheet on macOS)
- `TextInput+Maekster.swift` — `maeksterPlainTextInput()` (no autocorrection or capitalisation) and
  `maeksterURLInput()` (URL keyboard on iOS)
- `PlatformColor.swift` — `PlatformColor` typealias (`UIColor`/`NSColor`), `rgba()` / `hsba()` that also
  work for `NSColor`, and `Color.init(platformColor:)`
- `PlatformPasteboard.swift` — copying text to the general pasteboard
- `Color+Maekster.swift` — platform system colors (`maeksterSystemBackground`)

## macOS

maekster builds for macOS from the same target (#100). The iPhone UI in `Views/` is iOS-only and the Mac
UI in `MacViews/` macOS-only, file by file (Target Membership → platform). Everything else must compile
for both, which is what these wrappers are for.

## Related

- `Utilities/PlatformImage.swift` — `PlatformImage` typealias (`UIImage`/`NSImage`), `Image.init(platformImage:)`,
  `ImageRenderer.platformImage` and `NSImage.cgImage`; lives in Utilities because it is used by both the
  service layer and the UI layer
- `DesignSystem/Platform/Color+Maekster.swift` — platform-specific system color wrappers
