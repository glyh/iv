---
id: 012
title: Store decoded pixels in the backend's native format
labels: [wayfinder:task]
status: open
assignee: glyh
blocked_by: []
---

## Question

`iv` already says what a decode should produce:

- `src/core/bitmap.zig`: "A grayscale JPEG stays single-channel all the way to
  the screen."
- `docs/design/04-pixel-format.md`: "A format is an identity, not a channel
  count", over the set `gray8`, `rgb888`, `rgba8888`.

The JPEG backend has to be built that way, and there is one place where the
obvious implementation departs from it.

What the slice has to do:

- The shim stops setting `out_color_space` and reports what libjpeg actually
  produces (`output_components`): 1 for grayscale, 3 for colour.
- It reads scanlines straight into the `Bitmap`'s own rows. `gray8`'s stride is
  `w * 1` and `rgb888`'s is `w * 3`, exactly what libjpeg emits, so there is no
  intermediate row buffer and no per-pixel loop.
- `jpeg.zig` picks the `Format` from the component count, before allocating.
- **Four components is CMYK, not RGBA.** libjpeg's supported conversions are
  YCbCr => RGB, YCbCr => GRAYSCALE, RGB => GRAYSCALE, GRAYSCALE => RGB and
  YCCK => CMYK (`libjpeg.txt`), so there is no CMYK => RGB. It has no `Bitmap`
  format, so it is refused with its own error rather than mislabelled as
  `rgba8888` - which would invert the colours silently.
- The viewport uploads `gray8` (`GL_R8` plus a swizzle) and `rgb888`
  (`GL_RGB8`) as well as `rgba8888`.

## Done when

- `zig build test` proves `test/fixtures/gray.jpg` decodes to `gray8`,
  `test/fixtures/quadrants.jpg` to `rgb888`, and `test/fixtures/cmyk.jpg` is
  refused with a distinct error rather than `BadFile`.
- `zig build check` reads the colour fixture back through the viewport, which
  uploads RGB rather than RGBA.