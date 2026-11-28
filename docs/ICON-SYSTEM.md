# Lucide icons

Heavenly Axis renders an offline subset of Lucide 0.511.0, pinned to commit `ba77aa6a76152a93c0388910427c7ece3f75dd61`. The upstream SVG paths use a 24-unit grid and rounded strokes. The developer tool traces curves with a sampling tolerance of 0.22 SVG units, simplifies the sampled paths by 0.12 units and rounds coordinates to three decimal places. Circles and rounded rectangles retain dedicated native primitives. The standalone script includes the upstream ISC and Feather MIT notices through `src/LucideGlyphs.lua`. [Pinned Lucide source](https://github.com/lucide-icons/lucide/tree/ba77aa6a76152a93c0388910427c7ece3f75dd61) · [Lucide license](https://github.com/lucide-icons/lucide/blob/ba77aa6a76152a93c0388910427c7ece3f75dd61/LICENSE) · [Feather MIT license](https://github.com/feathericons/feather/blob/v4.29.2/LICENSE)

## Roblox implementation

- The renderer mounts passive `Frame`, `UICorner` and `UIStroke` instances. Icons fit inside independently sized action targets. Mounting has no asset requests, render loops or event subscriptions. Tint changes compare the root's current color before updating any strokes.
- Buttons retain their visible action labels. An unrecognized optional icon leaves the label usable. The editor's built-in renderer draws glyphs from bundled vector data.
- Backgrounds, borders, spacing, typography and touch minimums reuse the existing `Design.lua` tokens. Compact controls and viewports use the subset without adding a general UI framework.
- The structural Roblox mock mounted all 75 glyphs. Each icon averaged 22.59 descendants, with a maximum of 87. The most complex settings glyph fell from 149 to 87 descendants after generation-time simplification. These figures measure instance allocation in the fixture.

## Port comparison

| Source | Published implementation | Use in Heavenly Axis |
| --- | --- | --- |
| Lucide 0.511.0 | Upstream SVG paths under ISC with Feather attribution | Source for the bundled subset, with notices retained |
| `latte-soft/lucide-roblox` commit `11213a3a4938c5594e0765d8671f2af52c5ab47e` | Roblox atlas Asset IDs, cropping metadata and convenience factories under MIT and ISC | Reviewed for spritesheet performance and attribution. The editor uses a local renderer so its controls load without a separate texture dependency. |
| `Footagesus/Icons` commit `46d30c19ba7bc601d6ec794a48dc3a89568b1eec` | MIT wrapper with spritesheet lookups for multiple packs. Its executable entry point can load scripts and icon packs from mutable branches. | Reviewed for pack and atlas APIs. Offline, pinned glyph data fits the standalone distribution. |

[Latte Softworks source and license](https://github.com/latte-soft/lucide-roblox/tree/11213a3a4938c5594e0765d8671f2af52c5ab47e) · [Footagesus source and license](https://github.com/Footagesus/Icons/tree/46d30c19ba7bc601d6ec794a48dc3a89568b1eec)

## Regenerating the subset

The SVG parser is a contributor-only dependency. The shipped code uses the generated Luau table. To reproduce it, put the pinned Lucide `icons` directory and `LICENSE` in a local directory and add Feather v4.29.2's `LICENSE` as `Feather-LICENSE`. With `svgpathtools==1.7.2` installed in a development environment, run `python3 tools/lucide_subset.py <local directory> --check`. Omit `--check` to regenerate the table after making an intentional subset change, then regenerate the standalone bundle with the repository's existing build tool.
