---
id: 008
title: The GtkGLArea OpenGL viewport
labels: [wayfinder:task]
status: closed
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

## Answer

**The viewport is a `GtkGLArea` on OpenGL, drawing one textured quad.**

`src/shell/viewport.zig` owns it: resources are created once on the first
frame, the decoded `Bitmap` is uploaded whole and the GPU does the scaling, and
the quad is scaled by the fitted size so the image lands centred. The shaders
are `src/shell/shaders/image.{vert,frag}` as GLSL, embedded with `@embedFile`,
compiled and linked at first use - and a shader that fails to compile or link
prints the driver's own message instead of leaving a blank window.

The evidence is `zig build check`: it renders the committed fixture under
`xvfb-run` and reads two pixels back, and it fails when a shader breaks
(verified by breaking one).

Three qualifications:

- **Mipmap trilinear sampling did not land.** The ticket's premise named it,
  but it only pays off once zoom exists, so it moved to ticket 014 with the
  rest of the viewport's remaining work.
- **The `Viewport` interface is a concrete struct today.** The file's TODO says
  a second implementation is what earns a vtable.
- **A grayscale image is handled**: `upload` picks `GL_R8` and a swizzle for
  `gray8` as well as `GL_RGB8` and `GL_RGBA8`.