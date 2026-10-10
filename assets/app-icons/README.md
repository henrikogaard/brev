# Glass envelope icons

The approved family is 01 Frost, 02 Smoke (the default), and 03 Obsidian.
The six `source/brev-glass-*.svg` files are the editable masters. They contain
paths and gradients, with no raster images or blur filters. Historical PNG
concepts in `source/` are retained but are not inputs to the generator.

| Finish | Stable preference ID | Platform asset name |
| --- | --- | --- |
| Frost | `envelope-light` | `BrevIconEnvelopeLight` |
| Smoke | `envelope-dark-metal` | `BrevIconEnvelopeDarkMetal` |
| Obsidian | `envelope-carbon` | `BrevIconEnvelopeCarbon` |

Keeping the IDs also preserves existing settings backups. New preferences,
unknown IDs and Appearance resets select Smoke. Existing selections retain
the corresponding finish. Nightly uses Obsidian as its bundle icon.

## Regeneration

On macOS, install librsvg if needed (`brew install librsvg`), then run from the
repository root:

```sh
swift scripts/generate-app-icon-variants.swift
```

The script uses `rsvg-convert` for SVG rasterization and vector PDF export,
CoreGraphics to encode opaque iOS PNGs, and `iconutil` for alternate Dock ICNS
files. `SOURCE_DATE_EPOCH=0` keeps PDF metadata reproducible. Generated outputs
are committed, so ordinary builds do not need librsvg.

- Each raster size is rendered directly from SVG, with no additional inset.
- Logical sizes up to 64 pt use the compact drawing. macOS 128 px images also
  use compact artwork because they serve 48–64 pt Retina Dock slots.
- Settings and login images use PDFs with vector preservation enabled.
- All macOS Dock variants use multi-resolution ICNS, including 64 pt Retina artwork.
- iOS icon PNGs have a neutral opaque background and no alpha channel.
- `AppIcon.appiconset` supplies the primary icon. The retired Icon Composer
  resource is removed so it cannot add another background or replace Smoke.

The matching `brev-site` assets copy the Smoke SVGs. Page marks and favicons use
the compact drawing; the Apple touch icon uses the opaque 180 px iOS export.
