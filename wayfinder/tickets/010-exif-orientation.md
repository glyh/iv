---
id: 010
title: Apply EXIF orientation through an exiv2 shim
labels: [wayfinder:task]
status: open
assignee:
blocked_by: [001, 003]
---

## Question

Decision 01 makes orientation a decode concern, and decision 09 / ADR 0003 put
exiv2 behind a C shim. Implement the shim with the route ticket 001 proved (if
001 chose a C shim, this is the same recipe and no second C++ unit is needed),
read the orientation tag, and apply it with the rotate and flip that
`imageops.zig` already has.

- The shim's C functions are the only surface Zig sees (ADR 0003).
- A malformed EXIF block degrades to "no metadata", never to a failed decode
  (decision 09).
- Metadata is not a pixel buffer and does not count against the budget
  (decision 07b).

## Done when

- A committed fixture with orientation 6 comes out upright, asserted in a unit
  test with no display.
- A JPEG with a truncated EXIF block still decodes.
- The exiv2 include-path and linkage recipe in `build.zig` is the one ticket
  001 wrote, not a second variant.
