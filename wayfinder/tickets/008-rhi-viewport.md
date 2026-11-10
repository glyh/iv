---
id: 008
title: The QRhiWidget Vulkan viewport
labels: [wayfinder:task]
status: open
assignee:
blocked_by: [005, 006, 011]
---

## Question

Implement the `Viewport` seam of decision 12 with its first real
implementation: a `QRhiWidget` on the Vulkan backend drawing one textured quad
over a background, with mipmap trilinear sampling. That is the cheapest step in
`docs/research/qt-renderer-frontier.md`'s cost ordering, and the one that
removes zoom-out shimmer without a CPU rescale.

- Shaders are authored in the shell and compiled to `.qsb` by ticket 005's
  `qsb`, at build time.
- Everything RHI lives in one module (decision 12's mitigation for the private
  API); a Qt minor upgrade changing that API is a known hazard, so the Qt minor
  version is pinned.
- Device loss is handled through `QRhi::isDeviceLost()`, the widget's
  `renderFailed()` signal, and resource recreation in `initialize()`.

## Done when

- A committed solid-colour or gradient fixture draws through the viewport under
  the offscreen platform, or by hand with the evidence recorded.
- The renderer is reachable only through `Viewport`; no RHI type appears on
  the core side.
