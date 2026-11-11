---
id: 013
title: Probe without starting decompression, and pick the format by colour space
labels: [wayfinder:task]
status: closed
assignee: glyh
blocked_by: []
---

## Question

Two faults in the same place, and one fix answers both.

**The probe is nearly as expensive as the decode.** `iv_jpeg_probe` calls
`jpeg_start_decompress` to learn `output_components`, then throws the result
away and `iv_jpeg_decode` builds it all again. Measured on this machine, on a
600x640 photo, 400 runs each:

| | ms/call |
|---|---|
| `jpeg_read_header` only | 0.002 |
| the current probe (`jpeg_start_decompress` included) | 2.994 |
| decode | 3.408 |
| the two calls together | 6.402 |

So the second `jpeg_start_decompress` is 47% of the work of one image. Opening
the file twice is not the cost - that is two microseconds - the setup is.

**The format is chosen from a channel count, which is not an identity.** Three
components can be RGB, or a `JCS_UNKNOWN` file libjpeg passed through
untouched. `libjpeg.txt` says `jpeg_read_header`'s guess of the colour space
"can be relied on if the file conforms to JFIF or Adobe conventions, but
otherwise it is no better than a guess". Decision 04 says a format *is* an
identity, so the key has to be the colour space, not the count.

Both are fixed by reporting the colour space and reading only the header:

- `jpeg_read_header` already sets `out_color_space` from the file's own colour
  space, so nothing the caller needs is missing without
  `jpeg_start_decompress`.
- The shim reports one of its own colour-space values - gray, rgb, or other -
  and `jpeg.zig` maps that to a `Format`.
- `other` covers CMYK and anything libjpeg could not identify, and it is
  refused rather than guessed at. A colour space added on the C side without
  updating the Zig mapping lands in `other` too, so the failure is a refusal
  rather than a mislabelled image.
- `iv_jpeg_decode` re-derives the colour space after it starts and refuses to
  write when the component count does not match what the caller's format
  implies - defence in depth against the two calls disagreeing.

## Done when

- The probe no longer calls `jpeg_start_decompress`, and the two-call total
  drops by roughly the 47% measured above.
- `zig build test` still proves `gray.jpg` is `gray8`, `quadrants.jpg` is
  `rgb888`, and `cmyk.jpg` returns `UnsupportedColorSpace`.
- The colour tests measure a patch mean against the expected colour by squared
  RGB distance, not per-channel thresholds on two of three channels.

## Answer

**The probe reads the header and stops, and the format is chosen by colour
space.**

`iv_jpeg_probe` no longer calls `jpeg_start_decompress`. Nothing the caller
needs comes later: `jpeg_read_header` already sets `out_color_space` from the
file's own colour space, and the shim never requests a conversion. Measured on
the same 600x640 photo, 400 runs each:

| | before | after |
|---|---|---|
| probe | 2.994 ms | **0.002 ms** |
| decode | 3.408 ms | 3.306 ms |
| the two calls together | 6.402 ms | **3.308 ms** |

A 48% cut. Opening the file twice turned out not to matter - it is two
microseconds - while the second `jpeg_start_decompress` was most of a decode.

The shim reports `enum iv_jpeg_color_space` (gray, rgb, other) instead of a
component count, and `jpeg.zig` keys `formatFor` on that. `other` covers CMYK
and anything libjpeg could not identify, and it is refused with
`error.UnsupportedColorSpace`. The `else` arm is what makes it safe to extend: a
colour space added on the C side without a case in Zig is refused, not
mislabelled.

`iv_jpeg_decode` re-derives the colour space after it starts and returns
`IV_JPEG_BAD_FILE` when the component count that arrives does not match what the
caller's format implies, so the two calls cannot disagree into a buffer
overrun.

The colour tests now take a patch mean and compare by squared RGB distance
against the expected colour, instead of two per-channel thresholds that left
the green channel unconstrained.