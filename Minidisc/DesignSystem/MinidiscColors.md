# maekster Color System

## Palette overview

| Token | Light | Dark | WCAG | Permitted uses |
|-------|-------|------|------|----------------|
| `minidiscAccent` | `#D96B1F` | `#FF8C4B` | ~3.5:1 on white (large text AA) | Play button, scrubber progress, active shuffle/repeat toggle, tappable artist name |
| `minidiscAccentSecondary` | `#F5A06B` | `#FFB980` | decorative only | Gradient stop alongside `minidiscAccent`, tinted backgrounds |
| `minidiscAccentText` | white | white | — | Text/icons placed on an accent-filled surface |
| `minidiscCoverShadow` | rgba(0,0,0,0.15) | transparent | — | Shadow on cover art in light mode |
| `minidiscCoverBorder` | — | white 8% | — | Thin border on cover art in dark mode (replaces invisible shadow) |
| `minidiscLossless` | `#1E8A3C` | `#68D97D` | ~4.4:1 on white; ≥ 4:1 on artwork surfaces | Text of the lossless `FormatBadge` (FLAC, ALAC…) and its 18% tinted fill. Nothing else |

## Rules

1. **`minidiscAccent` is strictly for primary interactive elements.** It must never appear on body copy, captions, metadata labels, section headers, or timestamps.
2. **Accent contrast is AA for large text only** (~3.5:1 against white). All text using the accent color must be ≥ 18pt regular or ≥ 14pt bold.
3. **Text and backgrounds use SwiftUI semantic colors** (`Color.primary`, `Color.secondary`, `Color(.systemBackground)`, etc.). Do not add custom colors for text or backgrounds unless there is a concrete, justified need.
4. **Do not add new custom colors without updating this document.**

## Dark mode behavior

- Shadows on cover art are invisible against dark backgrounds. Use `.minidiscCoverStyle()` on all cover art views — it automatically switches to a 1pt border in dark mode.
- `minidiscAccentSecondary` is slightly warmer in dark mode to maintain perceived brightness.

## Adding a new color

1. Add the color set to `Assets.xcassets` with both Any and Dark Appearance variants.
2. Add a usage rule to this table.
3. Do not add a manual `Color` extension — Xcode generates `Color.<assetName>` automatically.

## Artwork surfaces (player, album, artist)

These screens are always dark. `ArtworkSurfacePalette.tint(from:)` keeps the cover's hue (chromatic
covers get ×1.3 saturation, capped at 0.85) and caps relative luminance at 0.1, so white text is at
least 7:1 and 70% white secondary text stays above 4.5:1. The page fades from that tint to a base at
32% of it. Before the cover colour is known the neutral is `Color(white: 0.09)`. Tappable artist
credits use `minidiscAccent` (dark variant) on these surfaces.

## Playlist artwork backgrounds

Immersive playlist pages use an image-derived background instead of a fixed asset colour.
PlaylistArtworkPalette preserves the sampled bottom-edge hue and limits its largest sRGB component
to 0.22. Missing artwork starts with a neutral 0.06 background. This keeps white titles and 65–70%
white secondary text readable even when the original cover is bright. At the brightest permitted
neutral background, contrast is about 11.7:1 for white and 6:1 for the 65% secondary text.

The original cover remains unmodified in the cache; a view gradient handles the transition into the
page. Manual theme overrides provide the source hue and receive the same dark treatment.

## Queue Builder genre tints

`GenreTint` gives each Discogs main genre a fixed colour so genres read apart at a glance on the
Discover card and the full Queue Builder page. Sub-genre pills use their main genre's tint.
"Other", decades and moods stay neutral (accent when picked), so colour always means genre.

- Unpicked pill: tint at 16% fill with a 55% outline; text stays `.primary`.
- Picked pill: solid tint with white text. Every tint keeps white at WCAG AA for normal text
  (4.8:1 for Jazz `#A6611C` up to 7.2:1 for Stage & Screen `#455A64`).
- The full page's genre columns use the tint at 8% as their background.

| Genre | Tint | Genre | Tint |
|-------|------|-------|------|
| Electronic | `#4B5BD6` | Rock | `#C0392B` |
| Jazz | `#A6611C` | Hip Hop | `#7D3C98` |
| Funk / Soul | `#B03A70` | Pop | `#C2185B` |
| Folk, World, & Country | `#5E6E22` | Blues | `#1F5FA8` |
| Reggae | `#2E7D32` | Classical | `#566573` |
| Latin | `#00796B` | Stage & Screen | `#455A64` |
| Non-Music | `#6B6B6B` | Brass & Military | `#7B5E52` |
| Children's | `#00737E` | | |

These are not asset colours: they only ever fill pills, never text or screen backgrounds, and are
the same in light and dark mode (the white-on-tint contrast holds in both).
