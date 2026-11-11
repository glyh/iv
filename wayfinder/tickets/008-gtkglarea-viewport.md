---
id: 008
title: The GtkGLArea OpenGL viewport
labels: [wayfinder:task]
status: open
assignee:
blocked_by: [006]
---

## Question

Implement the `Viewport` seam of decision 12 with its first real
implementation: a `GtkGLArea` on OpenGL drawing one textured quad over a
background, with mipmap trilinear sampling. That is the cheapest step in
`docs/research/qt-renderer-frontier.md`'s cost ordering - a Qt/QRhi-era
document, but its finding that mipmap sampling removes zoom-out shimmer without
a CPU rescale is API-agnostic and carries over, while its QRhi and `.qsb`
details do not.

- The area's `render` signal is connected with `g_signal_connect`; the shell
  does **not** subclass a widget (ADR 0001).
- Shaders are GLSL compiled in the shell's own GL context. There is no `.qsb`
  step and no Qt Shader Tools dependency (decision 12).
- Everything GL lives in one module; the `create-context` signal and a failed
  `realize` are where GL resources are built and rebuilt.
- The viewport needs a display, so its check runs under `xvfb-run`
  (decision 11).

## Done when

- A committed solid-colour or gradient fixture draws through the viewport under
  `xvfb-run`, or by hand with the evidence recorded.
- The renderer is reachable only through `Viewport`; no GL type appears on the
  core side.