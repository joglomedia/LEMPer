# LEMPer brand assets

LEMPer's identity builds on the welcome page: a rounded **L-plus** symbol,
purpose-drawn geometric lettering and a calm green palette. The L anchors the
name; the plus suggests installing and extending a stack. The compact tile works
as a browser icon, while the full wordmark spells the name **LEMPer**.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../.github/assets/lemper-logo-on-dark.svg">
  <img src="../.github/assets/lemper-logo.svg" width="424" alt="LEMPer horizontal logo">
</picture>

## Downloads

| Asset | Use |
|---|---|
| [Primary logo](../.github/assets/lemper-logo.svg) | Dark lettering on white or light surfaces; transparent background |
| [Logo for dark backgrounds](../.github/assets/lemper-logo-on-dark.svg) | Light lettering on forest or charcoal surfaces; transparent background |
| [Color icon](../.github/assets/lemper-icon.svg) | App tiles, avatars and favicons |
| [Monochrome icon](../.github/assets/lemper-icon-monochrome.svg) | Single-color printing and inline UI; transparent L-plus cutout |
| [Browser favicon](../.github/assets/favicon.ico) | Raster fallback with 16, 32 and 48 pixel sizes |
| [Welcome-page banner](../.github/assets/lemper-welcome.png) | README and project introductions; 1920 × 1080 PNG |

The logos and icons contain vector geometry, accessible titles and descriptions.
They contain no fonts, scripts, external resources or embedded bitmap images.
The monochrome icon uses `currentColor`: it inherits the surrounding text color
when inserted inline. As an external image, it defaults to black; set its fill
explicitly when preparing a different single-color export.

## Color system

| Token | Color | Purpose |
|---|---|---|
| Primary / forest | `#176B49` | Symbol, primary actions and links; a stable visual anchor that echoes the existing green identity |
| Ink | `#18382B` | Wordmark and headings on light surfaces |
| Paper | `#F8F9F4` | Light backgrounds and the L inside the symbol |
| Accent / lime | `#D9F39E` | The plus and small decorative details; adds warmth and energy |
| Muted | `#53655C` | Supporting copy on paper surfaces |
| Dark surface | `#0B251C` | Dark-background logo and presentation framing |

Use forest and ink for readable text on paper. Reserve lime for accents and
dark surfaces; it has insufficient contrast for small text on white. The palette
supports a composed, dependable presentation; readable contrast keeps the
interface clear.

## Typography and spacing

The SVG wordmark uses purpose-drawn, outlined lettering. Keep
its uppercase **LEMP** and lowercase **er**, letter spacing and proportions intact.

For UI and documentation visuals, use the system stack
`-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif`: weight 650–700 for
headings, 600 for labels and 400 for body text. Use
`ui-monospace, SFMono-Regular, Consolas, monospace` for commands and technical
labels. No web-font download is required.

Allow clear space of at least one quarter of the icon's height around the logo.
The logo viewBox is 424 × 96; the icon viewBox is 64 × 64. Keep their aspect ratios.
Use the full logo at 140 CSS pixels wide or larger. Use the icon below that size;
16 pixels is its minimum browser size, while 24–32 pixels is preferable for UI.
Do not stretch, add effects inside the symbol, recolor individual letters or put
the dark wordmark on a dark background.

## Presentation direction

Use flat vector artwork, generous space, restrained rounding and soft shadows
around screenshot frames. Preserve actual interface text in screenshots.

For a future raster presentation, use this art-direction prompt:

> Create a 1920 × 1080, 16:9 product presentation for LEMPer. Frame the supplied
> real welcome-page screenshot with rounded corners and a subtle shadow on a
> forest-green background, with a restrained lime glow. Keep the supplied logo,
> interface layout and text unchanged. Use clean, understated styling, crisp
> edges and generous margins. Add no extra text, devices, watermark or claims.

Create logo and icon variants from the SVG sources so their geometry stays
consistent. The raster prompt is for presentation backgrounds and framing.
