# 06 - Scaling: area prefilter, interpolate, in linear light

Status: decided

## The question

Which resampling filters does the core implement, and when is each used?

## Context

Scaling is resampling: shrinking 4000 pixels to 800 means combining several
source pixels into one, and the filter is the weighting.

- **nearest** - fastest, blocky when enlarged.
- **bilinear** - cheap, soft.
- **bicubic** - sharper, the common default.
- **Lanczos / windowed sinc** - sharpest, more expensive, can ring.

The defect a user actually notices is on **downscale**: sampling a 4000-pixel
image down to 800 with plain bilinear aliases fine detail into moire and
shimmer, which is very visible when scrolling a grid. The fix is a **low-pass
first**: average the source area each destination pixel covers, then
interpolate.

Two constraints were already known: interpolation must happen in
**premultiplied** space (decision 04), and on the GPU **mipmaps + trilinear** give
a good downscale almost for free (phase 2).

A third came out of measuring the libraries rather than reasoning about them:
**resampling happens in linear light**. A box average over encoded sRGB values
lands at RMSE 46.4 against the physically correct result; the same average in
linear light lands at 0.002. See `../research/3rd-party-abstractions.md`.

The reference viewer uses Qt's smooth scaling by default, optional OpenCV for "high
quality", and keeps two pixmap levels in the viewport.

## The options

1. **Two-stage**: area prefilter when shrinking by more than 2x, then
   bilinear/bicubic; Lanczos deferred.
2. Bilinear/nearest only.
3. Separable Lanczos3 with SIMD from day one.

## Decision

- **Downscale by more than 2x**: area-average the source region covered by each
  destination pixel, then interpolate.
- **Downscale by 2x or less**: bicubic (Catmull-Rom).
- **Upscale**: bicubic by default; bilinear available for live/preview paths.
- **All resampling happens in linear light**: convert the source from sRGB to
  linear, filter, convert back. This is not optional - the same kernel in encoded
  sRGB is 46.4 RMSE against the ideal, in linear light 0.002.
- All kernels in Zig with `@Vector`; no dependency. The rules the libraries
  encode are ours to keep, not their code.
- Interpolation is alpha-aware: premultiply, interpolate, unpremultiply.
- Lanczos is deferred; GPU mipmaps belong to the phase-2 renderer.

## Why

- Aliasing on downscale is the visible defect; the area prefilter removes it
  cheaply.
- Linear light is what separates a correct downscale from a plausible-looking one;
  the measurements put the gap at 46.4 vs 0.002 RMSE.
- Lanczos buys sharpness, which is subjective, at the cost of a separable
  multi-tap implementation and its tests - worth doing once a benchmark shows a
  visible difference.
- Bilinear-only keeps a known-visible defect.

## Consequences

- The scaler has two code paths and a threshold; the threshold is a named
  quality/performance knob, not a buried constant.
- The scaler owns an sRGB <-> linear conversion, and its tests compare against the
  linear-light area average.
- Live zoom (dragging) may use the cheaper filter and refine when the gesture
  settles, which interacts with decision 02's progressive results.
- These kernels are the first place Zig's `@Vector` earns its keep; treat them
  as a benchmark target.
