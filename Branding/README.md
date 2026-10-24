# maekster brand guide

This folder holds the logo, colours, fonts and rules for **maekster**. It lives in the
repository as `Branding/`. Treat every file here as a finished, read-only source: use it, but do not
edit or regenerate it. If something needs to change, the change happens in the design source and new
files replace these.

---

## 1. The name

| Where | How to write it |
|---|---|
| Logo artwork (SVG/PNG/PDF files in this folder) | **mækster** with æ. It exists **only** inside the logo files. |
| Everything else: app UI, strings, README text, docs, metadata, commit messages, URLs, file names | **maekster**, always lowercase, also at the start of a sentence |
| Swift type names | `Maekster…` (UpperCamelCase, as Swift requires), e.g. `MaeksterBrand` |
| Identifiers, keys, bundle-ID segments, URL schemes, folder and file names | `maekster` |

Never type "mækster" with æ as text. Never write "Maekster" (capital M) in prose or UI, and never
"MAEKSTER".

---

## 2. Logo

The logo has two parts: the **mark** (the orange ribbon folded into an m-shaped wave) and the
**wordmark** (mækster). The wordmark is drawn from Lexend Light with custom changes: the **m** has two
symmetric arches, the **r** has no spur, and the letter spacing is +0.06em. Because of those changes,
**never retype the wordmark in a font**. Always use the files.

### Versions

| Version | File | Use |
|---|---|---|
| Lockup, on dark backgrounds | `logo/svg/maekster-lockup-on-dark.svg` | README header (dark mode), website, desktop app, social |
| Lockup, on light backgrounds | `logo/svg/maekster-lockup-on-light.svg` | README header (light mode), documents |
| Mark, full colour | `logo/svg/maekster-mark.svg` | In-app brand moments (onboarding), favicons, avatars |
| Mark, one colour | `logo/svg/maekster-mark-mono-{black,white,orange}.svg` | Single-colour contexts: watermarks, embossing, template glyphs |
| Wordmark only | `logo/svg/maekster-wordmark-on-{dark,light}.svg` | Rare: where the mark already appears nearby |
| App icon | `logo/svg/maekster-app-icon.svg`, `logo/png/maekster-app-icon-1024.png` | App icon sources (opaque, square; iOS applies its own corner mask) |

"on-dark" means the file is for a dark background (light text). "on-light" means the file is for a light
background (dark text). The files have transparent backgrounds.

### Inside the iOS app

- Use the **mark** only, never the wordmark. The written name in the app is plain text: "maekster".
- The mark is in the asset catalogue as `BrandMark` (vector SVG, original colours).
- The app icon is an Icon Composer document (`xcode/AppIcon.icon`): a solid near-black fill
  (`#0E0E0E`) with the mark as one layer at 85% of the canvas width.

### Clear space and minimum size

- Keep clear space around the lockup equal to **half the mark's height** on every side.
- Minimum size of the lockup: **200 px (pt) wide** on screen. Below that, the Light wordmark becomes too
  thin to read, so use the mark alone.
- Minimum size of the mark: **20 px (pt) wide**. At favicon sizes (16 px), use the one-colour
  mark.

### Don't

- Don't retype, re-kern, outline, stretch or recolour the wordmark.
- Don't change the mark's colours or gradients, rotate it, or add effects (shadows, glows, outlines).
- Don't place the full-colour mark on orange or busy photos. Use the one-colour white mark there.
- Don't use the æ spelling outside the logo files.

---

## 3. Colour

### Brand colours (from the mark's gradients)

| Name | Hex | Role |
|---|---|---|
| Amber | `#FF9E23` | Highlight end of the ribbon |
| Orange | `#FE7619` | Core brand colour |
| Ember | `#E73703` | Shadow end of the ribbon |
| Ink | `#0E0E0E` | App icon background, dark surfaces |
| Paper | `#FAF8F5` | Light surfaces |
| Text on light | `#141414` | Wordmark and text on Paper (17.4:1) |
| Text on dark | `#FAF8F5` | Wordmark and text on Ink (18.2:1) |

Contrast: Amber, Orange and Ember all pass for text on Ink (9.3, 7.2 and 4.5:1). On Paper they do
**not** pass for body text (1.9, 2.5 and 4.0:1). On light backgrounds, use the brand oranges only for
graphics and large accents, never for text.

### iOS app colours

The app keeps its existing, contrast-tuned tokens. They are already in the same orange family as the
mark, so they do not change for the rebrand:

| Token | Light | Dark |
|---|---|---|
| `AccentColor` (global tint) | `#E8420E` | `#FF6242` |
| `minidiscAccent` | `#D96B1F` | `#FF8C4B` |
| `minidiscAccentSecondary` | `#F5A06B` | `#FFB980` |

The usage rules in `Minidisc/DesignSystem/MinidiscColors.md` still apply.

---

## 4. Type

| Context | Typeface |
|---|---|
| iOS app UI | System font (SF Pro) through the app's existing `.minidisc*` typography tokens. **No custom font is bundled in the app.** |
| Logo | Custom outlines (see section 2). Never set as live text. |
| Website, desktop app, marketing | **Lexend**: Light (300) for large headings, Regular (400) for body. For headings next to the logo, use Light with `letter-spacing: 0.06em`. |

Lexend is in `fonts/` (the variable font plus static Light and Regular). It is licensed under the
SIL Open Font License 1.1 (`fonts/OFL.txt`); keep that file with the fonts wherever you ship them.

---

## 5. Lineage and credits

maekster is a fork of [Minidisc](https://github.com/Loriage/Minidisc) by NO HIT Dev, which is itself a
fork of [Cassette](https://github.com/CassetteLab/cassette) by Mathieu Dubart. The code is under the
Mozilla Public License 2.0. Credit both projects in the README and in the app's acknowledgements.

---

## 6. File index

```
Branding/
├── README.md                         this guide
├── CLAUDE_CODE_PROMPT.md             the rebrand prompt used for the app
├── logo/
│   ├── svg/                          vector masters (use these first)
│   │   ├── maekster-lockup-on-dark.svg / -on-light.svg
│   │   ├── maekster-mark.svg
│   │   ├── maekster-mark-mono-black.svg / -white.svg / -orange.svg
│   │   ├── maekster-wordmark-on-dark.svg / -on-light.svg
│   │   └── maekster-app-icon.svg
│   ├── png/
│   │   ├── maekster-app-icon-1024.png            opaque, App Store
│   │   ├── maekster-mark-{256,512,1024,2048}.png transparent
│   │   ├── maekster-lockup-on-{dark,light}-2400.png
│   │   └── maekster-github-social-1280x640.png   GitHub social preview
│   └── pdf/                          mark and lockups as vector PDF
├── xcode/
│   ├── AppIcon.icon/                 Icon Composer document, replaces the app icon
│   └── BrandMark.imageset/           drop into Assets.xcassets
└── fonts/
    ├── Lexend[wght].ttf              variable, all weights
    ├── Lexend-Light.ttf, Lexend-Regular.ttf
    └── OFL.txt
```
