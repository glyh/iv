---
title: iv — from the skeleton to the first image on screen
labels: [wayfinder:map]
status: open
---

# iv — from the skeleton to the first image on screen

## Destination

`iv <path>` shows a real image file, fitted to the window, through the GTK4
shell and its `GtkGLArea` OpenGL viewport (design 12): the
decode → display path working end to end, on `trunk`, with the toolkit-free
parts covered by `zig build test`.

A **slice** is one commit-sized increment that leaves the tree building and
tested. Reaching the destination settles the libjpeg-turbo binding, the
decode-backend registry, the fit-and-size contract, the Zig–GTK boundary and the
zig-gobject build. The rest of the core — the byte-budget cache, the worker
pool, the freedesktop thumbnail cache, lcms2 colour, the remaining decode
backends — is beyond this destination and graduates from **Not yet specified**
when the frontier reaches it.

## Notes

**Where the design lives.** `docs/design/` is 13 decided documents (01 core
boundary … 13 repo strategy); `docs/adr/` holds the seven hard-to-reverse ones;
`CONTEXT.md` is the glossary. Code today: `src/core/bitmap.zig` (the pixel
type), `src/core/imageops.zig` (a deliberate first cut of scale/crop/flip/
rotate), `src/core/root.zig` (carries the intended build order as a TODO).

**Machine, measured 2026-11-10 (GTK4 on 2026-11-11).** Zig 0.17.0 (`/usr/bin/zig`); `zig build
test` and `zig build` both pass on a clean `trunk`. Every tier-2/tier-3 library that ships a `.pc`
resolves under pkg-config: libjpeg 3.2.1 (the `.pc` name is
`libjpeg`, not `jpeg`), libpng 1.6.59, libwebp 1.6.0, lcms2 2.20, exiv2
0.28.9, libtiff-4 4.7.2, libraw 0.22.3, libavif 1.4.2, libjxl 0.12.0, libheif
1.23.7, librsvg-2.0 2.63.4. Two do not: `stb_image` is vendored (decision
10), and GIF has `/usr/include/gif_lib.h` but no `giflib`/`libgif` `.pc`.
Headers for jpeg/png/webp/lcms2/exiv2/tiff are installed. **GTK 4.24.1** with
dev headers resolves under pkg-config (`pkg-config --modversion gtk4`), and
`zig translate-c` consumes the whole `gtk/gtk.h` with zero errors; the measured
recipe is `docs/research/gtk4-zig-interop.md`. The shell reaches GTK through
**zig-gobject** instead: `gobject-introspection` 1.86.0-2 is installed, and
`cairo-1.0.gir` and `freetype2-2.0.gir` are regenerated from their typelibs by
the build, because only the typelibs ship (`docs/research/zig-gobject.md`). GTK4 has **no offscreen GDK
backend** — `GDK_BACKEND=offscreen` answers "No such backend" — so anything
that needs a display runs under `xvfb-run`.

**Workflow, this effort (user, 2026-11-10).** No pull requests: land commits
directly on `trunk` and the user pushes. That overrides CLAUDE.md's "every
change arrives as a pull request"; commit subjects stay
`scope: imperative summary` and commits stay atomic.

**Verification (decision 11).** `zig build test`, no display. Where a ticket
needs a display — the GL viewport always does — run it under `xvfb-run`
(decision 12), and name that as the check in the ticket.

**Sequencing, and ADR 0002.** ADR 0002 builds the toolkit-free core (decode →
transform → thumbnail → cache) first and the application on top. This effort
interleaves the two phases on purpose: the destination is the first image on
screen, and the thumbnail contract, the byte budget and the worker pool are not
needed to reach it, so they stay in **Not yet specified**. If the interleave
sticks, ADR 0002 needs an amendment rather than being quietly ignored.

**Ticket shape.** This effort carries execution into the map: a ticket is
either a slice that lands code on `trunk`, or the decision that must be
settled immediately before a slice. `wayfinder/README.md` has the operations;
`wayfinder/frontier.sh` prints what is takeable.

## Decisions so far

- Install Qt Shader Tools (qsb) — moot; the viewport compiles GLSL in its own
  GL context. See ticket 005.
- How the shell gets a QRhiWidget the binding does not have — dissolved by the
  move to GTK4. See ticket 011.
- The Zig–GTK boundary and the shell's shape — the shell reaches GTK through
  `zig-gobject`; the rules live in `src/shell/root.zig`. See ticket 004.
- Store decoded pixels in the backend's native format — the JPEG backend keeps
  the file's colour space; CMYK is refused rather than mislabelled. See
  ticket 012.
- Probe without starting decompression, and pick the format by colour space —
  the probe reads the header only, and the format is keyed on the colour space
  rather than a channel count. See ticket 013.

## Not yet specified

- The core's request interface beyond one `decode(path, max)`: hints, the
  multi-result answer (preview then final), and where the budget accountant
  sits (decisions 02, 07b). Not sharp until the first image path shows what the
  shell actually asks for.
- The in-memory byte budget and the per-pixel-buffer LRU with pinning (07b),
  and the fixed worker pool with cooperative step cancellation (08). Both
  depend on the shape of the decode call and on the real size of in-flight
  decode buffers.
- The freedesktop on-disk thumbnail cache (07a, 07c): it needs a working
  decoder, the finished scaler, and a shell that asks for thumbnails by size.
- Colour management (05). How a display profile is obtained on this Wayland box
  is unknown, and while source and destination are both sRGB the step is a
  no-op, so it is not on the critical path.
- The remaining decode backends (PNG, WebP, TIFF, GIF first frame). Each is
  small; how many land in this effort is worth one decision once the JPEG
  backend exists.
- The renderer past the first quad: mipmap-only versus tiled upload versus GPU
  filters. `docs/research/qt-renderer-frontier.md` gives the cost ordering; it
  is a Qt/QRhi-era document, so its mipmap-sampling conclusion transfers and
  its QRhi specifics do not. Decide once a viewport exists and mid-zoom
  behaviour can be seen.
- Animation as a frame stream (GIF, animated WebP, APNG). Decision 03 defers
  it; the shell may keep a `GdkPixbufAnimation` path meanwhile.

## Out of scope

- Video playback and the mpv plugin (decision 01).
- Directory listing and watching, and the file model: the shell's, through GTK
  (decision 01).
- 16-bit pixels and an HDR path (decision 04).
- Qt, Qt Quick and game-UI stacks (decision 12); the qimgv C++ tree, vendored
  or subclassed (decision 13).
- A differential or conformance harness against qimgv as a gate (decision 11).
