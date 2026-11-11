# 12 - Phase 2 UI and renderer: GTK4 + GtkGLArea on OpenGL

Status: decided (2026-11, replacing the earlier Qt Widgets + QRhiWidget choice;
the trade-off is recorded in ADR 0007)

## The question

What UI stack and render path does the phase-2 application use?

## Context

- The app is a **desktop image viewer**. Native file dialogs, drag-and-drop
  from the file manager, IME (including CJK), accessibility, system
  theme/dark mode, hi-DPI and native menus are part of the product.
- **GTK4 is a C library**, and the shell reaches it through `zig-gobject`,
  whose bindings are generated from the installed GObject-introspection data
  rather than from a hand-picked class list. The `translate-c` route was
  measured too and works (`../research/gtk4-zig-interop.md`); the binding was
  chosen because it supplies typed signals and classes instead of hand-written
  wrappers. Both routes are measured in `../research/zig-gobject.md`.
- The earlier decision reached Qt through `libqt6zig`, a generated binding.
  That worked for a window and a button, but not for the viewport. Coverage
  gaps could only be closed by changing the generator upstream - not by editing
  anything in this repository - and the viewport's class, `QRhiWidget`, was one
  of the gaps.
  The binding also put C++ ABI rules (exceptions, RTTI) back in scope at every
  call site.
- **OpenGL, not Vulkan.** Qt exposes a public, non-deprecated `QVulkanWindow`,
  but `libqt6zig` does not bind it, so a Vulkan viewport on the Qt path meant a
  hand-written C++ `QWindow` subclass - which ADR 0001 forbids. GTK4 has no
  public Vulkan path at all: `GdkVulkanContext` is a
  `GDK_DECLARE_INTERNAL_TYPE` and `gdk_surface_create_vulkan_context` was
  deprecated in GTK 4.14 (this machine runs 4.24.1). Both offer a public OpenGL
  widget. So the binding was what blocked the viewport, and this decision
  forecloses Vulkan rather than rescuing it.
- Measured costs: GTK4 61 MB empty and 112 libraries, against Qt Widgets
  44 MB and 44 libraries and GTK3 33.9 MB and 69 libraries
  (`../research/gui-stack-weight.md`, re-measured in
  `../research/gtk4-zig-interop.md`). GTK4's larger footprint is accepted, not
  overlooked; GTK3's smaller one is rejected on trajectory - see ADR 0007.

## Decision

- The shell is **GTK4**, reached through **`zig-gobject`** at a pinned
  revision, with its generator run as part of `zig build` so the bindings match
  the installed GTK and no generated code is committed.
- The image viewport is a **`GtkGLArea` on OpenGL**, drawing one textured quad.
- The renderer sits behind a small `Viewport` interface in the shell, so it can
  be replaced (a software `GtkDrawingArea`, or a different GL widget) without
  touching the core.
- Shaders are GLSL handed to the GL area from the shell. There is no `.qsb`
  step and no Qt Shader Tools build dependency.

## Why

- Desktop integration is the product, and GTK4 supplies it as plain C:
  `GtkFileDialog`, drag-and-drop, `GtkIMContext`, accessibility, dark mode and
  hi-DPI are all present in the translated headers.
- The failure mode changes rather than merely shrinking: the binding is
  generated from the system's own introspection data, so there is no
  hand-curated list to fall off, and it binds C, so no C++ ABI rule sits at the
  call site. That is the reason this decision was reopened, and the reason to
  prefer GTK4 over Qt Widgets despite the measured memory cost.
- `GtkGLArea`'s `render` is a **signal**, so the shell connects to it and does
  not subclass a widget - consistent with ADR 0001's refusal of C++
  subclassing.
- The renderer is isolated behind an interface, so the decision stays
  reversible at the shell level and never reaches the core.

## Consequences

- **A heavier toolkit.** +17 MB at rest and 2.5x the library closure, against
  the rule the earlier research applied. Recorded as a deliberate exception in
  ADR 0007.
- **OpenGL, not Vulkan.** The earlier "no OpenGL" rule is withdrawn. The
  renderer module is the only place that knows which API is used.
- **GL context loss is handled in one place**: `GtkGLArea` can fail to realize
  or lose its `GdkGLContext` (the `create-context` signal), and every GL
  resource is rebuilt there.
- **Initialization is checked.** `gtk_init_check()` returning false must stop
  the shell: GTK does not guard later calls, and `gtk_window_new()` after a
  failed init segfaults (observed in the research harness).
- **The build grows a codegen step.** `zig build` runs `zig-gobject`'s
  generator over the installed GIR files, so a build machine needs
  `gobject-introspection` and the GIR XML for GTK's closure - on this machine
  `cairo-1.0.gir` and `freetype2-2.0.gir` are regenerated from their typelibs.
  The recipe is in `../research/zig-gobject.md`.
- **Testing needs a display.** GTK4 has no offscreen GDK backend -
  `GDK_BACKEND=offscreen` answers "No such backend" - so display-free tests
  cover the shell's non-GL parts and the GL path runs under `xvfb-run`
  (decision 11).
- Phase 2 does not block the core: the core hands out bitmaps and never knows
  which renderer consumes them.