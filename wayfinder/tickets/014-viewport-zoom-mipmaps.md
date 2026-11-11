---
id: 014
title: Zoom, pan and mipmap sampling in the viewport
labels: [wayfinder:task]
status: open
assignee:
blocked_by: []
---

## Question

Ticket 008 landed the viewport: one textured quad, the image fitted and
centred, and the pixels verified by `zig build check`. What it left is the
rest of the viewport's behaviour, which the shell's TODO has been pointing at
ticket 008 for.

- **Zoom and pan.** Today the quad is scaled once, from `fitWithin`, and never
  moves. The scale is already a uniform, so this is input handling plus a
  transform, not a renderer rewrite.
- **Mipmap sampling.** The premise of ticket 008 was trilinear-from-mipmaps
  rather than a linear filter, and `docs/research/qt-renderer-frontier.md` is
  where that cost ordering comes from (a Qt/QRhi-era document: its mipmap
  conclusion is API-agnostic, its QRhi and `.qsb` details are not). It only
  pays off once zooming out exists, which is why it is here and not there.
- **Tiled or mipmap-only upload** for oversized images, once it is clear which
  one mid-zoom behaviour wants.
- **The `Viewport` interface.** A concrete struct is honest while there is one
  implementation; a second one is what earns a vtable (decision 12).

## Done when

- Zooming and panning keep the image correct at both ends: 1:1 and well
  below it, judged by `zig build check` on pixels rather than by eye.
- A zoomed-out image no longer shimmers, with the mechanism recorded.
- The shell's TODO in `src/shell/root.zig` names this ticket instead of 008.