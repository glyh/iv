# exiv2 behind a C shim inside the core

Status: accepted

The core needs EXIF orientation (decode-critical) and basic tags. libexif is
plain C and would keep the core C-only, but its own README says maker notes are
only partly handled. exiv2's tag depth is worth more than that purity here, so
the core carries exactly one C++ translation unit, wrapped in an `extern "C"`
shim and compiled by Zig's own clang against the system libstdc++ (recipe in
`../research/zig-cpp-interop.md`). Full reasoning: `../design/09-exif-metadata.md`.

## Considered options

- **libexif (plain C)**: rejected on maker-note coverage.
- **A hand-rolled orientation reader**: rejected because EXIF byte order, IFD
  offsets and vendor quirks are easy to get subtly wrong, and the failure mode -
  a sideways photo - is hard to diagnose.

## Consequences

- The core is no longer pure Zig/C, and cross-compilation inherits the
  libstdc++ requirement that any C++ program has.
- A malformed EXIF block degrades to "no metadata", never to a failed decode.
