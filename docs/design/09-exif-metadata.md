# 09 - EXIF and metadata: exiv2 behind a C shim

Status: decided (ADR 0003)

## The question

Which metadata library does the core use, and where does metadata live?

## Context

EXIF is metadata stored inside the image file: camera make and model, exposure,
GPS, timestamps, and **orientation** - which way the camera was held.

Two consumers with different weight:

- **Orientation is decode-critical**: without it, a photo displays sideways or
  upside down. Decision 01 already accepted that metadata enters the core for
  this much.
- **Display metadata** (the info panel, sorting) is closer to the shell, but the
  core is already parsing the block, so returning it is nearly free.

The libraries:

- **exiv2** - C++ API, the deepest tag set including vendor maker notes.
- **libexif** - plain C, all EXIF 2.1 and most 2.2, but its own README says maker
  notes are only partly handled.
- **a hand-rolled parser** - anything you do not parse is unavailable, and EXIF
  byte order / IFD offsets / vendor quirks are easy to get subtly wrong.

## The options

1. libexif in the core, keeping it C-only.
2. exiv2 behind a C shim. **(chosen)**
3. A hand-rolled orientation-only reader.

## Decision

**exiv2, wrapped in a C shim that lives in the core.** Metadata is returned
separately from pixels, so it costs nothing against the pixel budget. libexif was
explicitly weighed and rejected: for this app, maker-note depth is worth more
than keeping the core C-only.

## Consequences

- **The core now contains exactly one C++ translation unit.** The C functions the
  shim exports are the only surface the Zig side sees.
- That unit is compiled by **Zig's own clang**, against the system libstdc++
  headers. Zig bundles clang and libc++, but exiv2 is a libstdc++ library, so
  the shim must use libstdc++ headers and link system libstdc++.
  The verified recipe - and the correction of an earlier wrong claim that Zig's
  clang could not parse gcc-16 headers at all - is in
  `../research/zig-cpp-interop.md`.
- "The core builds with `zig build` alone" therefore still holds. Decision 10 is
  about documenting the include-path and linkage recipe, not about adding a
  second compiler.
- Metadata must never block the image: a malformed EXIF block degrades to "no
  metadata", never to a failed decode.
