# 04 - Pixel format: 8-bit gray/RGB/RGBA, straight alpha

Status: decided

## The question

What pixel formats does the core guarantee, at what bit depth, and in which
alpha representation?

## Context

A pixel format is how one pixel's bytes are laid out: how many channels, in what
order, and whether there is a transparency channel. The core's `Bitmap` already
has gray8 (one channel), rgb888 (three) and rgba8888 (four), all 8 bits per
channel.

- **Bit depth**: 8 vs 16 bits per channel. 16 bits is what HDR and camera RAW
  need; the cost is that the format matrix, the scaler kernels, the colour
  transforms and the tests all double.
- **Alpha**: *straight* keeps colour separate from transparency, so a fully
  transparent pixel still holds its real colour. *Premultiplied* stores colour
  already multiplied by alpha; GPUs and Qt's fast paths prefer it, but the
  colour of a fully transparent pixel is lost.
- **A hard technical fact**: interpolating pixels that carry alpha must be done
  in premultiplied space, or transparent edges pick up dark or coloured halos.
  Storage and interpolation therefore do not have to use the same
  representation. Skia's managed draw makes this explicit: it unpremultiplies
  before colour management and premultiplies again on the way out.

## The options

1. **8-bit gray/RGB/RGBA; straight alpha storage; premultiply inside the
   resampler; 16-bit deferred.**
2. 16-bit from day one, with an explicit colour pipeline, for HDR/wide gamut.
3. Premultiplied ARGB32 as the internal representation, matching Qt.

## Decision

1. The core guarantees **gray8, rgb888, rgba8888**. The format is an enum that
   can grow, but no v1 backend produces more than 8 bits per channel.
2. **Storage is straight alpha.**
3. Any operation that interpolates pixels (scaling, rotation with filtering)
   **premultiplies, interpolates, then unpremultiplies**.
4. A display surface that wants premultiplied pixels gets them at the UI
   boundary, not in the core.

## Why

- Almost every input is 8-bit. Adding 16-bit before there is a consumer (an HDR
  display path) doubles the format matrix, every kernel and every test for no
  viewer-visible gain today.
- Straight alpha is the lossless representation, which is what transforms and
  colour management want to operate on.
- Premultiplication is a property of *interpolation*, so it belongs where
  interpolation happens, not in the storage format.
- Option 3 imports Qt's historical trade-off - losing colour under transparency -
  which hurts the edit-and-save path.

## Consequences

- **The scaler must be alpha-aware.** A naive per-channel average of two
  rgba8888 pixels is wrong at transparent edges; the premultiply-interpolate-
  unpremultiply step is not optional.
- 16-bit later means adding formats and doubling the kernels. The code must not
  assume 8 bits per channel anywhere: byte counts already derive from the
  format's channel count, and that has to stay true.
- The core cannot hold a 16-bit colour-managed intermediate until then, so
  colour management runs on 8-bit input.
