# 03 - Decode backends: a registry, one module per library

Status: decided.

## The question

How does the core decide which decoder handles a given file?

## Context

Decoding is turning compressed bytes back into pixels. Each format compresses
completely differently - JPEG stores frequency coefficients, PNG stores
filtered rows, AVIF stores AV1 video frames - so no single code path covers
them. The choice is made by looking at the first few bytes, the **magic
bytes**: a JPEG starts with `FF D8`, a PNG with `89 50 4E 47`.

The reference viewer leaves all of this to Qt's QImageReader, which dispatches to
format plugins. That dispatch is invisible and untouchable; a toolkit-free core
needs its own.

## The options

1. **Backend registry** - a list of backends, each declaring the formats it
   claims, a probe over the first bytes, and a decode entry. The core asks them
   in a fixed order; the first that claims the bytes *and* succeeds wins.
2. **Central switch** - sniff one format id, then switch to a direct call. Fewer
   moving parts, but every new format edits the switch and a backend cannot be
   tested alone.
3. **One big library for everything** (ImageMagick or similar) - least code, but
   the core inherits that library's quality, memory behaviour and dependency
   weight, and loses easy decode-time downscaling and partial decode.

## Decision

**A backend registry**, with the shape imv uses: a backend is a struct with a
name, the formats it claims, a probe (`does this look like mine?`) and a decode
entry taking bytes (or a path) plus a maximum size. The core iterates in a fixed
order and stops at the first backend that both recognizes the input and decodes
it.

## Why

- Decisions 02's scheduler and progressive results need each backend to
  describe its own behaviour: can it downscale during decode, can it emit
  progressive results, how much memory does it allocate in flight. A registry
  gives that a home; a switch does not.
- A backend is unit-testable alone: hand it magic bytes and a fixture and assert
  the result, with no other backend present.
- imv proves the shape in a real viewer, including the three-way result that
  matters below.

## Consequences

- **A probe has three outcomes, not two**: (a) recognized and decoded, (b)
  recognized but the data is broken - stop and report, do not try the next
  backend, (c) not recognized - try the next. imv's SUCCESS / BAD_PATH /
  UNSUPPORTED split is the model, and getting it wrong produces either a wrong
  decoder silently winning or a corrupt file being reported as an unknown format.
- Probes must be cheap and allocation-free: they run on every unknown file.
- Order matters and must be documented, because containers masquerade: many
  camera RAW formats are TIFF underneath, so the RAW backend must be asked
  before a generic TIFF backend.

## Animation (decided)

The v1 core handles **still images only**. Animation - GIF, animated WebP,
APNG - becomes a separate, later interface: a frame stream carrying per-frame
timing, looping and disposal rules. Until that interface exists an animated file
decodes as its first frame, and the shell keeps a GdkPixbufAnimation path
(gdk-pixbuf ships with GTK4) so animation does not visibly regress during the
transition.

Why: stills are the overwhelming majority of the app, and the budget, scheduler
and progressive-stream designs are all about a single image. Animation adds
wall-clock timing, disposal and a different memory model - frames retained over
time - and bundling it now would complicate the still path before that path is
stable.

## Backend set (decided)

Three tiers, in the spirit of the optional-dependency flags the reference
viewer's build uses (`-Dexiv2`, `-Dopencv`, `-Dkde`):

- **Tier 1, always present**: JPEG (libjpeg-turbo), PNG (libpng), and
  `stb_image` as a catch-all for BMP/TGA/PSD/HDR/PIC. Small, no build flags.
- **Tier 2, default-on when the library is found**: WebP, TIFF, GIF first frame.
- **Tier 3, explicit flags, default off**: AVIF (libavif + dav1d), JPEG XL
  (libjxl), HEIF (libheif), SVG (librsvg), camera RAW (libraw). Starts empty.

An absent backend is simply absent from the registry; no build special-casing,
because the registry already handles "nothing recognized this".

Why tiers: dependency weight and CVE surface scale with format count, and
decoders take untrusted input. Tiering keeps a bare system buildable and puts
the heavy, patent- and platform-sensitive libraries behind opt-in. TIFF and WebP
are common enough to be on by default; dav1d, libjxl and libraw are not worth
the day-one build and packaging burden.
