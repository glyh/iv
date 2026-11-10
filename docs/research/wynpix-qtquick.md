# Why Wynpix chose Qt Quick, and what it cost

Read 2026-11 from the repository itself: `hadoooooouken/Wynpix` (default branch
`main`), `docs/ARCHITECTURE.md`, `CMakeLists.txt`, and the file tree. This is
the one project in the Qt image-viewer family that left Qt Widgets, so its
reasons are the best available evidence for decision 12.

## What it is

A Windows-optimised qimgv fork: C++26, Qt 6.12, 259 C++ files and 99 QML files.
The README says the viewer "renders every image on the GPU through Qt Quick
(Direct3D 11 by default; Direct3D 12 or Vulkan can be selected with the
`quickGraphicsApi` key in the configuration file)".

## What its architecture doc actually says

The migration is described as **finished**, and it is built on a UI-agnostic
core:

- `Core` is a mediator that talks to the UI **only through ports**:
  `INotificationPort`, `IDialogPort`, `IViewerPort`, `IShellPort`,
  `IWindowPort`, `IViewModePort` outbound, plus an inbound `UiEvents` signal
  set. `QuickUiHost` implements those ports with the Qt Quick UI.
- Stated principles:
  1. **No business logic in QML** - QML binds, lays out, animates and forwards
     intent; decisions stay in C++.
  2. **Core gains no responsibilities** - new features are separate `QObject`
     components behind explicit interfaces.
  3. **One GPU path** - "every pixel on screen goes through the Qt Quick scene
     graph on QRhi"; image filtering, tone mapping, colour management and
     downsampling are RHI shaders.
  4. **Render-thread discipline** - Qt Quick's threaded render loop means renderer
     objects never touch `Core` or `Settings`; data crosses only in
     `synchronize()` / `updatePaintNode()`, as immutable values.
- Two **memory budgets** bound decoded pixels, both scaled to installed RAM
  (`scaledToInstalledMemory`, `utils/decodebudget.h`): preloading stops at
  1.5 GiB on a 16 GiB machine (at most 8 GiB); thumbnails from readers that
  cannot scale on read share 1 GiB on 16 GiB (at most 4 GiB).
- Heavy QML sits behind `Loader { active: false; asynchronous: true }` so the
  first frame does not pay for dialogs and the folder view.
- RHI failures (device loss, failed `create()`, a shader that will not load)
  reach controllers through explicit signals.

## The intuitive benefits, stated plainly

1. **The device, swapchain and render loop come for free.** Qt Quick already
   owns a render thread, vsync, texture management and per-frame batching; the
   app plugs in through `QQuickRhiItem`. A Widgets app must build that itself on
   `QOpenGLWidget` (OpenGL only) or the newer `QRhiWidget`.
2. **Backend choice without per-API code.** QRhi abstracts D3D11/D3D12/Vulkan/
   Metal/OpenGL, which is why Wynpix can expose a `quickGraphicsApi` setting.
3. **One technology for image and UI.** GPU filters, HDR tone mapping, colour
   LUTs, panoramas, HUD animations and the shell are all the same render path,
   instead of a GPU image inside a CPU-painted widget tree.
4. **Declarative shell.** QML makes overlays, animations and interactive
   controls quick to write; the cost is a second language and its tooling
   (`qt_add_qml_module`, qmlcachegen, `.qsb` shaders, `.rcc` modules).
5. **Testability.** `QQuickRhiItem` renders offscreen, so the renderer can be
   tested headless - which qimgv cannot do at all today.

## The costs, from the same sources

- **The UI had to be decoupled first.** The ports layer is what made the swap
  tractable; without it, the migration would have touched the core.
- **Qt Quick is heavier at rest.** The fork's own measurement: Qt Quick 182.6 MB
  RSS empty against Qt Widgets' 44.1 MB (both under software rendering).
- **Two languages and their tooling**, plus render-thread rules that are easy to
  violate.
- **Windows-first**: D3D is the default path, and the fork's ambitions (real-time
  AI upscaling, HDR, GPU colour adjustment, panoramas) are what justify the GPU
  investment.

## What it implies for decision 12

Qt Quick buys GPU-everything; the price is a UI-agnostic core (ports) plus a QML
shell. If iv wants GPU filters/HDR/panoramas, Qt Quick is the coherent
choice. If it wants a fast, correct viewer with today's feature set, the fork's
own measurements say GPU does not move the dominant costs (decode memory,
directory/load latency), and `QGraphicsScene` - which seven of nine Qt viewers
in the family use - is the cheaper path. The middle option is `QRhiWidget`
(Qt 6.7+), which puts RHI rendering inside a Widgets shell without the QML
migration; it exists in this Qt 6.12 tree.
