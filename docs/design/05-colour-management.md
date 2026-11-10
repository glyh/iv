# 05 - Colour management: a transform step in the core, source pixels preserved

Status: decided

## The question

Does the core do colour management, where does the transform run, and does it
keep the original pixels?

## Context

A photo's numbers only mean something in a colour space (sRGB, AdobeRGB, Display
P3, ...). The file usually carries an **ICC profile** saying which space that is;
the display has its own characteristics. Colour management maps file numbers to
display numbers so the image looks as intended. Without it, wide-gamut photos
look flat and desaturated.

Skia's model is the clearest statement of what the transform is: every space
describes a transform to and from a connection space, **XYZ D50**, and a managed
draw is six steps (unpremultiply, linearize, 3x3 to XYZ D50, 3x3 to the
destination gamut, encode, premultiply).

The reference viewer does **none** of this: there is no QColorSpace and no ICC handling
anywhere in the tree. It treats every file and every display as sRGB.

The C engine is **lcms2** (Little CMS), a full ICC 4.4 implementation. On Linux
the display profile is often unavailable (X11 has no standard path; Wayland's
colour-management protocol is new), so the destination will usually be sRGB for
a while.

## The options

1. **A transform step in the core** (lcms2), with the source pixels and profile
   preserved.
2. Bake the sRGB conversion into decode.
3. No colour management in v1.

## Decision

- Decode stores the decoded pixels **and the source colour profile** separately;
  a file with no profile is assumed sRGB.
- The core offers a colour transform operation taking pixels + source profile +
  destination profile, implemented with lcms2.
- It sits on the **cache -> display** path, and its result is cacheable under the
  same byte budget.
- When source and destination agree, or there is no profile and the destination
  is sRGB, it is a **no-op**.
- The shell owns which destination profile to use, the rendering intent, and
  whether to apply the transform at all.

## Why

- Zero cost in the common case (sRGB file, sRGB display), correctness when it
  matters.
- Preserving the source pixels is required for edit and save, and lets the
  transform move to the GPU later without re-decoding.
- Caching the transformed result fits the budget that already exists.

## Consequences

- lcms2 becomes a dependency (small, C).
- The core needs a place to carry a profile with a bitmap: a bitmap + profile
  pair, or a decoded-image struct.
- Until the shell can obtain a real display profile, the destination is sRGB and
  the step mostly no-ops. That is not wasted work: the plumbing and the profile
  preservation are the hard parts.
- A renderer-side GPU LUT remains available later; it changes where the step
  runs, not the decision to keep source pixels and a profile.
