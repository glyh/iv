# 12 - Phase 2 UI and renderer: Qt Widgets + QRhiWidget on Vulkan

Status: decided

## The question

What UI stack and render path does the phase-2 application use?

## Context

- The app is a **desktop image viewer**. That means native file dialogs,
  drag-and-drop from the file manager, IME (including CJK), accessibility,
  system theme/dark mode, hi-DPI and native menus are part of the product.
- The measurements in docs/research/: Qt Widgets 44 MB empty; Qt Quick 182.6 MB; SDL3
  149 MB under software GL; dvui 214 MB. Qt Quick and SDL ship no native
  integration for the list above, and a game-UI stack would make all of it
  hand-built.
- GPU rendering does **not** move the dominant costs (decode memory,
  directory/load latency); it moves frame pacing and mid-zoom scaling quality.
- `QRhiWidget` (Qt 6.7+) renders through QRhi **inside a Widgets app**, with a
  selectable backend: Vulkan, D3D11, D3D12, Metal or OpenGL. It does not require
  OpenGL.
- Alternatives weighed: `QGraphicsScene`, Qt Quick + `QQuickRhiItem` (Wynpix's
  path), wgpu (Dawn/`zgpu`) in a native child window, a game-engine UI stack.

## Decision

- The shell is **Qt Widgets** - not Qt Quick, not a game UI stack.
- The image viewport is a **`QRhiWidget` using the Vulkan backend**; no OpenGL.
- The renderer sits behind a small `Viewport` interface in the shell, so it can
  be replaced (a QGraphicsScene fallback, or a wgpu surface) without touching the
  core.
- Shaders are authored and compiled to `.qsb` with `qsb` (Qt Shader Tools) at
  build time.

## Why

- Desktop integration is the product; Qt Widgets supplies it and is the lightest
  measured option.
- `QRhiWidget` gets GPU rendering with Qt-supported widget integration, avoiding
  the native-surface embedding that wgpu would require - and that embedding is
  where the Wayland private-API fragility lives.
- Vulkan satisfies "no OpenGL" without introducing a new graphics API dependency
  (Dawn) and its surface glue.
- The renderer is isolated behind an interface, so the decision is reversible at
  the shell level, not the core.

## Consequences

- **Private Qt API.** The QRhi headers live under QtGui's versioned private
  include directory (`.../QtGui/6.12.0/QtGui/rhi/`); the build needs
  `qt6-base-private-dev`, and a Qt minor upgrade can change the API. Mitigations:
  confine every RHI call to one module, pin the Qt minor version, keep the
  `Viewport` interface.
- **`qsb` is a build-time dependency** (Qt Shader Tools). It is not installed on
  this machine yet.
- **Device loss must be handled**: `QRhi::isDeviceLost()`, the widget's
  `renderFailed()` signal, and resource recreation in `initialize()`.
- **Testing**: `grabFramebuffer()` allows headless pixel checks of the renderer,
  but still needs a working RHI backend under the offscreen platform.
- Phase 2 does not block the core: the core hands out bitmaps and never knows
  which renderer consumes them.
