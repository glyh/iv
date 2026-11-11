# GTK4 from Zig: what the shell would actually be built on

Researched 2026-11-11 on this machine (Zig 0.17.0, GTK 4.24.1, Qt 6.12.0).
Every claim below was run, not recalled.

## The question

Decision 12 chose a Qt Widgets shell reached through `libqt6zig`. The trigger
for re-opening it was concrete: `QRhiWidget` is not in that binding, so the
viewport the decision asked for cannot be built without forking the generator.
The question here is whether a **GTK4** shell - a C library, reached the same
way every other C dependency in this project is reached - removes that class of
problem, and what it costs.

## 1. `@cImport` no longer exists, for C or for C++

The starting assumption was that a C library can be `@cImport`ed directly.
On Zig 0.17.0 it cannot - the builtin was removed:

```
$ zig build-obj /tmp/cimport_stdio.zig
/tmp/cimport_stdio.zig:1:11: error: invalid builtin function: '@cImport'
const c = @cImport({ @cInclude("stdio.h"); });
```

That fails on `stdio.h`, so it is not a GTK problem. In 0.17 every foreign
library goes through the build system: **C** through `addTranslateC`
(decision 10), **C++** through a hand-written `extern "C"` shim
(`../research/zig-cpp-interop.md`). The gap between the two is therefore
narrower than "C is easy, C++ is hard" - but it is not closed, because
translate-c consumes a C header directly and a C++ library needs a shim per
entry point.

## 2. `translate-c` consumes the whole GTK4 header cleanly

```
$ zig translate-c $(pkg-config --cflags-only-I gtk4) /tmp/gtk_wrap.h > /tmp/gtk_translated.zig
exit 0, stderr empty
98,948 lines of Zig
```

Only the include paths are wanted here. The full `pkg-config --cflags gtk4` also
carries `-mfpmath=sse -msse -msse2 -pthread`, and translate-c rejects the first
with `error: unrecognized parameter: -mfpmath=sse`.

The output is valid Zig and compiles:

```
$ zig build-obj /tmp/gtk_translated.zig -lc
exit 0, 0 errors
```

Every API the shell needs was present in the translated output, including the
ones that decide the shape of the shell:

| symbol | present |
|---|---|
| `gtk_init` | yes |
| `gtk_window_new` | yes |
| `gtk_gl_area_new`, `gtk_gl_area_get_context` | yes |
| `gdk_surface_create_vulkan_context` | yes (deprecated, see section 4) |
| `gtk_file_dialog_new` | yes |
| `gtk_im_context_simple_new` | yes |
| `gtk_graphics_offload_new` | yes |

## 3. End to end: it builds, links and runs

A throwaway project at `/tmp/gtkbuild/` - a `build.zig` with
`b.addTranslateC` over a one-line wrapper header, the include paths from
`pkg-config --cflags-only-I gtk4`, `linkSystemLibrary("gtk-4")` for the link
flags, and a 14-line `main.zig` - built with `zig build` and ran under `xvfb-run`:

```
$ zig build && xvfb-run -a ./zig-out/bin/gtkprobe
gtk_init_check -> 1
gtk_window_new non-null -> true
gtk_gl_area_new non-null -> true
gtk_file_dialog_new non-null -> true
gtk_im_context_simple_new non-null -> true
```

The `build.zig` API on 0.17 is worth recording, because it is not the shape
the older documentation shows: `linkSystemLibrary` lives on the **module**
(`exe.root_module.linkSystemLibrary("gtk-4", .{})`), not on the compile step,
and `TranslateC` has its own `addIncludePath` / `linkSystemLibrary`.

### There is no offscreen backend

GTK4 has no `GDK_BACKEND=offscreen`, so it does not offer the display-free
window path Qt's `QT_QPA_PLATFORM=offscreen` does:

```
$ GDK_BACKEND=offscreen ./zig-out/bin/gtkprobe
Gdk-WARNING: No such backend: offscreen
gtk_init_check -> 0
Segmentation fault at address 0x0
```

Two consequences. A display-free check of anything that builds a window is not
available, so those checks run under `xvfb-run`. And GTK does not guard calls
made after a failed init - the probe called `gtk_window_new()` after
`gtk_init_check()` returned false and crashed - so the shell must check the
result and stop.

## 4. The binding, not the toolkit, is what blocked the viewport

This is the finding that reframes the decision. Decision 12 chose
`QRhiWidget` on **Vulkan** and explicitly rejected OpenGL. Checked against both
bound sets:

| | Qt 6.12 via libqt6zig | GTK 4.24.1 via translate-c |
|---|---|---|
| app-owned Vulkan | **absent from the binding** - but `QVulkanWindow` and `QVulkanInstance` are public, non-deprecated `Q_GUI_EXPORT` classes in Qt itself | `GdkVulkanContext` is `GDK_DECLARE_INTERNAL_TYPE`; `gdk_surface_create_vulkan_context` is `GDK_DEPRECATED_IN_4_14` |
| app-owned OpenGL | `QOpenGLWidget`, `QOpenGLContext`, `QOpenGLFunctions` **bound** | `GtkGLArea`; `render` is a signal, connectable without subclassing |

The two columns are not the same claim, and the difference is the finding.

- **Qt has a public Vulkan path that this project could not reach.**
  `qvulkanwindow.h:66` declares `QVulkanWindow` as a public `Q_GUI_EXPORT`
  class with no deprecation macro, and it is meant to be subclassed for exactly
  this. It is missing only from `libqt6zig`, so a Vulkan viewport on the Qt
  path meant a hand-written C++ `QWindow` subclass - which ADR 0001 forbids.
- **GTK4 has no public Vulkan path at all.** `gdkvulkancontext.h` marks
  `GdkVulkanContext` `GDK_DECLARE_INTERNAL_TYPE`, and `gdksurface.h` marks the
  surface constructor deprecated as of GTK 4.14 (this machine runs 4.24.1).

So the binding was what blocked the viewport, not the toolkit - and moving to
GTK4 does **not** rescue Vulkan, it forecloses it. Accepting OpenGL is a
separate amendment to decision 12, forced by GTK4 and made necessary on the Qt
path too by ADR 0001. What both toolkits offer is a public OpenGL widget.

## 5. Binding coverage, and what a gap costs

libqt6zig's own coverage figures are 96.4% of QtWidgets and 85.4% of QtGui, and
`libqt6zig.md` asks that they be read as directional. The classes this shell
would touch were checked by name against `include/libqt6.zig`: `QWidget`,
`QMainWindow`, `QFileDialog`, `QMenu`, `QAction`, `QToolBar`, `QStatusBar`,
`QScrollArea`, `QListView`, `QAbstractItemModel`, `QFileSystemModel`, `QImage`,
`QPixmap`, `QPainter`, `QDragEnterEvent`, `QSettings`, `QShortcut`, `QTimer`,
`QThread`, `QLabel`, `QVBoxLayout`, `QSplitter`, `QGraphicsScene`,
`QGraphicsView` and `QOpenGLWidget` are all bound; `QRhiWidget` is not, and
neither is any other member of the RHI and Vulkan family. The only RHI-shaped
class in the package is Qt Quick's `QQuickRhiItem`, which decision 12 ruled out.

The cost of closing a gap is not a local edit. The package on disk is
generated output - `modules.zig`, 1,420,824 lines across `include/` (3,263 of
them in the top-level `libqt6.zig`) and 1,671 per-class `.cpp` files, with no
generator in it - and its README says the
bindings are based on the
[MIQT bindings for Go](https://github.com/mappu/miqt). Adding a class is
upstream work in the generator, i.e. a fork or a wait. **GTK4 has no
equivalent step**: translate-c reads the installed headers, so every API the
headers declare is available the day the headers are installed.

## 6. What it costs

Re-measured here, with GTK3 included because it is installed and is the one
option that beats Qt Widgets on memory.

| | GTK4 4.24.1 | GTK3 3.24.52 | Qt 6.12 |
|---|---|---|---|
| dependency closure | **112** libraries | **69** libraries | **44** libraries |
| RSS, empty window (`gui-stack-weight.md`) | **61 MB** | **33.9 MB** | **44 MB** |
| RSS, +5,000 items | 64 MB | 40 MB | 64-84 MB |

The library counts are `ldd` on the library itself, which includes the library's
own line; `gui-stack-weight.md` recorded 113 and 45 for the same GTK4 and Qt
libraries, a difference of exactly that line. The RSS figures are that
document's, not re-measured here.

GTK4 is heavier at rest and pulls 2.5x the libraries. It also links
`libvulkan` through GDK regardless, so the closure includes the thing the
OpenGL decision declines to use.

## What this means for iv

- GTK4 is reachable two ways, and both were measured: `translate-c` over the
  installed headers (this document), and `zig-gobject`'s generated bindings
  (`zig-gobject.md`). The shell uses the binding; this document is the evidence
  that the C route works if the binding is ever dropped.
- The viewport is `GtkGLArea` on OpenGL, and `render` is a signal, so the
  shell does not subclass a widget (which matters to ADR 0001).
- Shaders are GLSL handed to `GtkGLArea`; there is no `.qsb` step and no
  `qt6-shadertools` build dependency.
- The price is +17 MB resident and +68 libraries against Qt Widgets, and it is
  a price this project chose to pay deliberately, for the reasons the shell
  decision records.

## Not established

- The RSS of an actual iv GTK4 shell: no shell exists, so section 6 is a
  bare-window comparison, not an iv measurement.
- Any real-GPU number; everything here and in `gui-stack-weight.md` is
  software rendering under Xvfb.
- Accessibility, IME and dark-mode behaviour under GTK4 in this app - the
  APIs exist and are C, but no behaviour was exercised.
- GTK3 is installed here (3.24.52; the `.pc` name is `gtk+-3.0`, not `gtk3`,
  which an earlier probe got wrong) and is the one option lighter than Qt
  Widgets. It is left out of the decision on trajectory, not on measurement;
  the shell decision records why.