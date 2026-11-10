---
id: 009
title: Put the first decoded image on screen
labels: [wayfinder:task]
status: open
assignee:
blocked_by: [003, 008]
---

## Question

Join the two halves: `iv <path>` decodes the file at the window's size (ticket
003) and draws it fitted in the viewport (ticket 008). This is the destination
slice.

- Ask the decoder for a size that fits the window, per ticket 002's contract;
  never decode whole and shrink.
- Handle the three outcomes a file can have: decoded; recognized but broken;
  not recognized. A bad file produces a message; it does not crash or exit.
- Orientation is **not** in this slice. Until ticket 010 lands, a photo whose
  EXIF orientation is not 1 shows sideways; that gap is left as a TODO in the
  code naming ticket 010.

## Done when

- A committed JPEG fixture appears fitted to the window, shown by an offscreen
  `grabFramebuffer()` check or by a hand run with the evidence recorded.
- A truncated or non-image file produces a message and the app stays up.
- `zig build test` still covers everything that needs no display.
