# Moon-Lander brand assets

The pink Moonrockz bunny pilots a gold lunar lander. The art uses the same pink
fur, white muzzle, navy outlines, painted shading, lunar setting and white
lettering as the Moonrockz, Smithy and Diagrams logos. Gold landing hardware is
the Moon-Lander accent.

Open [preview.html](preview.html) to compare all three designs on light and dark
backgrounds and see the small icons at their actual sizes.

## Logos

| File | Use |
| --- | --- |
| [moon-lander-badge.png](moon-lander-badge.png) | Primary logo with the lunar scene and `moon-lander` wordmark |
| [moon-lander-mark.png](moon-lander-mark.png) | Standalone bunny and lander, without text or scenery |
| [moon-lander-icon.png](moon-lander-icon.png) | Simplified bunny portrait and gold cockpit for small displays |
| [../moon-lander-badge.png](../moon-lander-badge.png) | 480 x 480 copy for the repository README |

The three originals are PNGs with transparent backgrounds. Keep them when making
new sizes. They are raster artwork; there is no SVG source. Use the icon rather
than the full badge for favicons and small navigation elements.

## Icons

| File | Size | Use |
| --- | --- | --- |
| [icons/favicon.ico](icons/favicon.ico) | 16, 32 and 48 px PNG entries | Browser favicon |
| [icons/favicon-16.png](icons/favicon-16.png) | 16 x 16 | Small favicon |
| [icons/favicon-32.png](icons/favicon-32.png) | 32 x 32 | PNG favicon |
| [icons/favicon-48.png](icons/favicon-48.png) | 48 x 48 | Large favicon |
| [icons/logo-64.png](icons/logo-64.png) | 64 x 64 | Site header |
| [icons/apple-touch-icon.png](icons/apple-touch-icon.png) | 180 x 180 | Touch icon |
| [icons/icon-192.png](icons/icon-192.png) | 192 x 192 | App icon |
| [icons/icon-512.png](icons/icon-512.png) | 512 x 512 | Large app icon |

Each PNG is resized from `moon-lander-icon.png` with alpha preserved. The ICO
contains the three favicon PNG files without repainting them. On macOS, make a
new PNG size with `sips -z SIZE SIZE moon-lander-icon.png --out OUTPUT.png`.

When copying the icons into a site's public asset folder, use links such as:

```html
<link rel="icon" href="/favicon.ico" sizes="16x16 32x32 48x48">
<link rel="icon" type="image/png" href="/favicon-32.png" sizes="32x32">
<link rel="apple-touch-icon" href="/apple-touch-icon.png" sizes="180x180">
```

Use the site's base path before these filenames when it is hosted under a path.

## Sources and prompts

Generated with the built-in image_gen tool. The exact prompts and reference
roles are in [generation-prompts.txt](generation-prompts.txt).

Visual references:

- [Moonrockz organization mascot](https://github.com/moonrockz/smithy/blob/main/site/public/moonrockz.png)
- [Smithy badge](https://github.com/moonrockz/smithy/blob/main/docs/assets/brand/smithy-badge-1024.png)
- [Diagrams badge](https://github.com/moonrockz/diagrams.mbt/blob/main/docs/assets/brand/diagrams-badge.png)
