# The shell is GTK4 on OpenGL, and its footprint is an accepted cost

Status: accepted (2026-11)

Decision 12's earlier choice - Qt Widgets through the generated `libqt6zig`
binding, with a `QRhiWidget` viewport on Vulkan - is withdrawn. The shell is
GTK4, reached through `zig-gobject`'s generated bindings, with a `GtkGLArea`
viewport on OpenGL.

## Why this reverses an earlier decision

The binding was the problem, not Qt's language. `libqt6zig` is a hand-curated
class list - 96.4% of QtWidgets, 85.4% of QtGui - over a C++ library, and its
generator lives upstream, so a class it does not bind cannot be added by
editing anything in this repository: the fix is a fork or a wait. The viewport
needed exactly such a class, `QRhiWidget`, and it is absent along with the
whole RHI and Vulkan family.

GTK4 is reached through `zig-gobject`, which is also a binding, so the point is
not that this project avoids one. It is that the two bindings fail differently.
`zig-gobject` generates from the installed GObject-introspection data, which
`g-ir-scanner` derives from the library's own public API, so its coverage is
complete by construction for whatever the system provides; and it binds C, with
no C++ ABI rules at the call site. The evidence is `../research/zig-gobject.md`.

Separately, Vulkan was not available on either path. Qt **does** expose a
public, non-deprecated `QVulkanWindow` meant for exactly this - it is missing
only from `libqt6zig`, so a Vulkan viewport there meant a hand-written C++
`QWindow` subclass, which ADR 0001 forbids. GTK4 has no public Vulkan path at
all: `GdkVulkanContext` is an internal type and its surface constructor was
deprecated in 4.14. So the binding was the blocker, and this move forecloses
Vulkan rather than rescuing it; OpenGL is accepted on both paths.

## The trade-off, stated plainly

`../research/gui-stack-weight.md` measured GTK4 as the heavier toolkit and
concluded that no toolkit replacement was defensible **under the rule that a
change must win on time or memory**. This decision does not clear that bar:

| | GTK4 | GTK3 | Qt Widgets |
|---|---|---|---|
| empty-window RSS | 61 MB | 33.9 MB | 44 MB |
| dependency closure | 112 libraries | 69 libraries | 44 libraries |

The project pays +17 MB and +68 libraries **against Qt Widgets**, plus a
build-time dependency on `gobject-introspection` and the GIR files, to trade a
hand-curated C++ binding for a C one generated from the system's own
introspection data. That is a deliberate exception to the rule,
recorded here so a later reader does not conclude the measurement was ignored.
GTK3 is the option that would have cleared the rule and is rejected anyway; see
below. The core boundary and the `Viewport` interface keep the swap cheap if the
figure ever becomes the binding constraint.

## Considered options

- **Keep Qt and amend ADR 0001 to allow one C++ subclass.** Rejected: it keeps
  the binding and its generator as standing dependencies, and the subclass is
  the one thing ADR 0001 exists to refuse.
- **Keep Qt and use the bound `QOpenGLWidget`.** This closes the immediate gap
  with no binding work and is the honest alternative. Rejected because the
  binding remains, and the next missing class is the same problem again.
- **GTK3.** Measured lighter than both alternatives (33.9 MB empty against Qt
  Widgets' 44.1 and GTK4's 61), plain C, and reachable by `translate-c` with no
  binding layer. Rejected on trajectory rather than measurement: GTK3 is the
  previous line, GNOME's development happens on GTK4, and building a new
  application on it trades a known memory win for an unknown amount of future
  porting. This is the option that would have cleared the memory rule.
- **A Zig-native UI stack (`dvui`).** Rejected earlier on measurement;
  unchanged by this decision.

## Consequences

- ADR 0001 is restated for GObject signals instead of Qt signals.
- The build gains a pinned `zig-gobject` revision, a codegen step, and a
  `gobject-introspection` requirement, and loses `libqt6zig`, the Qt private
  headers and `qt6-shadertools`.
- The shell cannot lean on Qt's raster widgets; every widget is a GTK call.
- The bindings are generated from the installed GIR data, so they track the
  system's GTK rather than a version iv chooses.