# The resampler is ours, with the two rules the libraries taught us

Status: accepted

We implement the scaler rather than depend on `stb_image_resize2` or libvips. The
measured cost of writing it is small, and the rules that make it correct are short:

1. **Downscaling prefilters.** Average the source area each destination pixel
   covers, not a point sample. One-pass bilinear aliases: RMSE 71.7 against the
   ideal, and a 1-pixel checkerboard comes out with std 38.3 instead of flat.
2. **Resampling happens in linear light.** The same box average in encoded sRGB is
   RMSE 46.4; in linear light it is 0.002. `stb_image_resize2`'s `_srgb` entry
   point is the only library path measured that applies this; libvips' `resize`
   and `thumbnail` do not, on a profile-less sRGB image.

Both rules are taken from the libraries' behaviour - their headers/docs and the
measurements in `../research/3rd-party-abstractions.md` - but the implementation
stays ours: 8-bit RGBA, in process, no new dependency.

## Consequences

- The scaler carries an sRGB <-> linear conversion. Decision 06 as written did not
  mention it; this ADR is what makes it part of the design.
- Tests compare against the linear-light area average, the same metric the
  measurements use.
- libvips remains available and bindable (translate-c verified) if format coverage
  or a demand-driven pipeline is ever wanted; this decision is about the scaler
  only.
