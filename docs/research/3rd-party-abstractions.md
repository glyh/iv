# Third-party abstractions for the core: what exists, what to adopt

Before accepting the skeleton, the question was whether a library already provides
the abstractions the core hand-rolls. Read and **run** on this machine, 2026-11.

## What the skeleton hand-rolls

| piece | today | note |
|---|---|---|
| `Bitmap` + `Format` | ~30 lines | the pixel type, and a three-value format enum |
| `imageops` | ~280 lines | scale (nearest/bilinear), crop, flipH/V, rotate90, fitWithin |
| planned | - | backend registry, colour step, cache, pool |

## 1. The pixel type and its format matrix

**zigimg** (github.com/zigimg/zigimg, ★859) already has this abstraction.
`PixelFormat` is a packed `{ bits_per_channel: u8, channel_count: u4, variant:
PixelFormatVariant }` encoded into a `u32` enum, with the full matrix:
`indexed1..16`, `grayscale1..16`, `grayscale8Alpha`, `grayscale16Alpha`,
`rgb332/555/565`, `rgb24`, `rgba32`, `bgr24`, `bgra32`, `rgb48`, `rgba64`,
and float variants. `Image` is the buffer (`fromRawPixelsOwned`, `create`,
`pixelFormat`), and the tree has `PixelFormatConverter.zig` and `simd.zig`.

That is the model our `Format` enum hand-rolls - and a strict superset: it carries
bits-per-channel and a BGR variant, which is exactly what the RGBA-vs-CMYK
discussion needs.

zigimg has **no** resize, rotate, colour or cache: a tree search for
`resize|scale|rotate|transform` returns only `color.zig`.

## 2. Resampling

- **stb_image_resize2** - single header, public domain / MIT, filters
  `STBIR_FILTER_BOX|TRIANGLE|CATMULLROM|MITCHELL`, sRGB-aware, 8- and 16-bit;
  defaults are CATMULLROM up and MITCHELL down. **The copy inside `nothings/stb`
  is deprecated in-tree** ("This version is deprecated"); the maintained home is
  `nothings/stb_image_resize`. Zig packaging exists: `zig-gamedev/zstbi`
  (stb_image + stb_image_resize + stb_image_write).
- **libvips** - `vips_resize` (with `vips_resize_interpolate(kernel)`),
  `vips_thumbnail`, plus `reduce/shrink/affine/similarity` and Google-Highway
  SIMD variants (`reduceh_hwy.cpp`, `shrinkh_hwy.cpp`).
- **libyuv** - scale/convert/rotate, C, YUV-first. **zimg**, **Skia**, **OpenCV**
  are C++ (`zigcv`, `zopencv` bindings exist for OpenCV).

Nothing Zig-native does resampling.

## 3. The whole pipeline: libvips

libvips is the only library that has the complete set the core designs:

- **loaders**: `libvips/foreign/*load.c` - jpeg, jxl, heif, nsgif, openexr,
  pdfium, openslide, magick, ...
- **geometry and resample**: `resize`, `thumbnail`, `reduce`, `shrink`,
  `affine`, `similarity`, `crop`, `rot`
- **colour**: `vips_icc_transform` (lcms2 underneath)
- **cache and threads**: `vips_cache_set_max_mem(size_t)` and
  `vips_concurrency_set(int)` (`libvips/iofuncs/cache.c`, `thread.c`)
- **pixel access**: `vips_region_new`, `vips_image_write_to_memory`

**It is already installed here**: `pkg-config --modversion vips` gives **8.18.7**,
with glib 2.90.1, gdk-pixbuf 2.44.8 and `/usr/bin/vips`.

**And Zig can bind it - verified, not assumed.** `zig translate-c` over
`vips/vips.h` succeeds and emits **43,660 lines**, in which every operator the
core needs is a `pub extern fn`: `vips_init`, `vips_image_new_from_file`,
`vips_thumbnail`, `vips_resize`, `vips_rot`, `vips_crop`,
`vips_icc_transform`, `vips_cache_set_max_mem`, `vips_concurrency_set`,
`vips_image_write_to_memory`, `vips_region_new`. The GObject machinery
(`G_DEFINE_TYPE` everywhere) does **not** prevent it. No hand-written C shim.

## What adopting libvips would delete

Decisions **02** (requests + budget scheduler), **03** (backend registry), **05**
(colour step), **06** (scaler) and **08** (pool), and most of **07** (its cache
knobs replace ours, though not the freedesktop on-disk thumbnail layout, which
stays ours).

That is a lot of code not written, and a real change in what the project is: the
Zig layer becomes a wrapper around a C library, which is the opposite of the
"idiomatic Zig core" goal. It also commits the build to a GObject dependency tree
(glib, gio, gdk-pixbuf, cairo, pango, ... - present here, but a packaging promise)
and to ~44k lines of generated bindings.

## Measured, not argued

Same input, same target, one machine (8-core Core Ultra 7 258V). Input: a
4096x4096 RGB pattern - a 1-pixel checkerboard and 1-pixel stripes (maximum
aliasing), a gradient and a radial zone plate - downscaled to 512x512 (8x).
"Quality" is RMSE against the physically correct result: the 8x8 area average
computed **in linear light**, converted back to sRGB. Lower is better.
\`checkerboard_std\` is the spread inside the checkerboard corner, which must be
flat; a high value is aliasing.

| implementation | RMSE | max diff | checkerboard std |
|---|---:|---:|---:|
| \`imageops\` bilinear (what the skeleton ships) | **71.7** | 188 | **38.3** |
| area prefilter in sRGB (decision 06 as written) | 46.4 | 61 | 0.0 |
| **area prefilter in linear light** | **0.002** | 1 | 0.0 |
| \`stb_image_resize2\` \`stbir_resize_uint8_srgb\` (Mitchell) | 3.6 | 93 | 0.02 |
| libvips \`vips resize --kernel lanczos3\` | 45.6 | 74 | 0.0 |
| libvips \`vips resize --kernel mitchell\` | 45.7 | 74 | 0.0 |
| libvips \`vips reduce 8 8\` (box) | 46.4 | 78 | 0.01 |
| libvips \`vips thumbnail\` (CLI) | 45.6 | 74 | 0.0 |
| \`vipsthumbnail\` (CLI) | 45.6 | 74 | 0.0 |

Wall time, one run, process start included: \`imageops\` bilinear 0.022 s, stb
0.028 s, \`vips resize\` lanczos3 0.090 s, \`vips thumbnail\` 0.059 s,
\`vipsthumbnail\` 0.086 s. The CLI numbers carry ~40 ms of libvips start-up; in
process they would be closer.

### What the numbers say

1. **The dominant term is linear light, not the algorithm.** The sRGB-space box
   and libvips' three resize paths all land at ~46 - the same gamma error. The
   same box in linear light lands at 0.002. stb's \`_srgb\` entry point is the only
   library path measured that applies the linear-light step.
2. **The prefilter is the second term.** One-pass bilinear aliases badly (std 38.3
   on a field that must be flat).
3. **libvips does not beat a hand-rolled box here.** On a profile-less sRGB image
   its \`resize\` and \`thumbnail\` resample the encoded values; you must convert
   to linear first for the good result.
4. **Speed is not the reason to hand-roll.** stb is within 30 % of the naive
   bilinear, and libvips' CLI numbers are start-up-dominated.

### Consequence

- Decision 06's two-pass scaler is **not enough as written**: it must also do the
  resampling in linear light, or it is no better than a plain box (46 vs 0.002).
- With that step, a ~40-line Zig kernel matches the ideal on this test and is the
  fastest of the group; a library is then a convenience, not a quality requirement.
- If a library is preferred, stb's \`_srgb\` path is the one to take.

## Recommendation

- **Adopt the format model**: zigimg's `PixelFormat` is the abstraction for the
  pixel matrix; our three-value enum is a subset of a solved problem. Taking the
  model (or the type) removes a class of "is 4 channels RGBA or CMYK" questions
  before they are asked.
- **Do not hand-roll the resampler.** It is the piece with the most quality risk.
  `stb_image_resize2` is small, MIT/public-domain, filter-based and sRGB-aware;
  `vips_resize` is the heavier, SIMD-accelerated alternative.
- **libvips is the "just use it" answer** for the whole core, and it works from Zig
  today. Take it if the goal is to ship a fast viewer with less code. Skip it if
  the goal stays a Zig codebase whose core is ours. That is a product decision,
  not a technical one.
- **Middle path**: keep the small Zig core, take zigimg's format model, take a C
  resampler, keep lcms2 and the C decoders for format coverage.
