---
id: 007
title: Rewrite the scaler in linear light
labels: [wayfinder:task]
status: open
assignee:
blocked_by: []
---

## Question

`src/core/imageops.zig` says of itself that it is a first cut: `nearest` and
`bilinear` only, and `bilinear` reads straight alpha, so a transparent edge
blends against un-premultiplied colour. Decisions 04 and 06 replace it:

- premultiply, filter, unpremultiply: interpolation is alpha-aware;
- area prefilter when shrinking by more than 2x, bicubic (Catmull-Rom)
  otherwise, bilinear kept for live gestures;
- all resampling in linear light (sRGB to linear, filter, back). The
  measurement behind it, in `docs/research/3rd-party-abstractions.md`, is
  RMSE 0.002 for the linear-light average against 46.4 for the same average in
  encoded sRGB;
- `@Vector` kernels, the first place in this codebase where Zig's vectors earn
  their keep.

This ticket is independent of the decode path and off the destination's
critical path (the first image is fitted by the viewport), so it can be taken
in parallel with 001-003.

## Done when

- Unit tests compare against hand-computed linear-light area averages, and an
  RGBA fixture pins the transparent-edge behaviour.
- A gray/RGB/RGBA image round-trips through the scaler within one 8-bit step at
  unity scale.
- The `imageops.zig` TODO is gone, or restated to match what is actually left
  (for example Lanczos).
