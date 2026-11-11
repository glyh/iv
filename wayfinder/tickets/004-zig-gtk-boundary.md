---
id: 004
title: The Zig-GTK boundary and the shell's shape
labels: [wayfinder:grilling]
status: closed
assignee: glyh
blocked_by: []
---

## Question

Decision 12 chose GTK4, reached by `translate-c`; the recipe was measured end
to end in `docs/research/gtk4-zig-interop.md`. Before any shell code exists,
settle the rules that keep the boundary honest.

Settle:

- **Which module owns every GTK call.** GTK is a C library, so there is no
  exception to catch and no C++ ABI rule at the call site - unlike the
  `libqt6zig` path this replaces. Decide whether the shell wraps GTK behind a
  thin Zig layer or calls `gtk_*` directly, and write the rule where the shell
  code will live.
- **Where the `Viewport` seam sits** (decision 12) and what crosses it. The
  plan: the core hands out a `Bitmap`, and the shell hands nothing back into
  the core.
- **How the shell keeps "every event has exactly one consumer"** (ADR 0001)
  across GObject signals: which GTK signals the shell connects with
  `g_signal_connect`, what the callback's `callconv(.c)` shape is, and how a
  worker reaches the main thread (`g_main_context_invoke`).
- **The layout under `src/shell/`** and the `GtkApplication` lifecycle: who
  owns it, and what ends the event loop. `gtk_init_check()` failing must stop
  the shell - GTK does not guard later calls, and a call after a failed init
  segfaults (observed in the research harness).
- **The build recipe**: `addTranslateC` over a wrapper header, the include
  paths from `pkg-config --cflags-only-I gtk4`, and
  `exe.root_module.linkSystemLibrary("gtk-4", .{})` for the link flags. On Zig
  0.17 that is a module method, not a compile-step one, and it does not add the
  include paths - those are the explicit step above. The full
  `pkg-config --cflags gtk4` also carries flags translate-c rejects.

## Done when

- The rules are written where the shell code will live, not only in this
  ticket.
- Any term the shell introduces is in `CONTEXT.md`, or is a word the glossary
  already defines.

## Answer

**The shell reaches GTK through `zig-gobject`, and the rules are written into
`src/shell/root.zig`.**

The boundary question changed shape while it was being settled. It started as
"wrap GTK in a Zig facade, or call `gtk_*` directly", and the answer was the
facade. Then the maintained-binding question was asked, and the answer is
better: `zig-gobject` is the only live Zig binding for GTK
(`docs/research/zig-gobject.md`), it generates from the installed GIR data
rather than a hand-picked class list, and a probe written for iv builds and runs
`GtkGLArea` under Xvfb. So the shell imports the generated modules and writes no
facade of its own.

Settled, and recorded in `src/shell/root.zig`:

- **Reaching GTK**: the shell imports the `gtk`, `gdk`, `gio` and `glib`
  modules. It does not hand-write a binding layer and does not `translate-c` the
  GTK headers itself. The binding is the interop boundary, so a misbehaving GTK
  call has a search space of the generated module plus the pinned revision.
- **The `Viewport` seam**: a `*const Bitmap` and a target rectangle cross it;
  the implementation uploads and draws, the fit arithmetic stays in the shell,
  and nothing crosses back into the core.
- **Events**: GTK's signals are consumed through the binding's typed
  `signals.<name>.connect`, which carries a `user_data` pointer - no
  `g_signal_connect` and no `GCallback` cast in the shell. An app-internal event
  stays a plain Zig callback with one consumer (ADR 0001); a worker reaches the
  main thread through `g_main_context_invoke`.
- **Lifecycle**: `main.zig` builds a `GtkApplication` and calls
  `g_application_run`; its status is the process exit status and where a failed
  GTK init surfaces. Any direct `gtk_init_check` must be checked - GTK does not
  guard later calls.
- **Build**: a pinned `zig-gobject` revision whose generator runs as a build
  step, needing `gobject-introspection` on the build machine.

**Found while settling this, and left for ticket 008**: the binding has no
`GL-1.0` module, because only its typelib is installed and there is no `.gir` to
generate from. The viewport's `gl*` calls therefore come from a `translate-c`
over `epoxy/gl.h` (GTK already links `libepoxy`) or over `GL/gl.h` with
`libGL`. It is a `TODO` in `src/shell/root.zig`.

**Adopting a binding re-opens ADR 0007's argument, and it is restated there**:
the point is no longer that GTK4 has no binding layer, but that `zig-gobject`
generates from the system's own introspection data (complete by construction)
and binds C, where `libqt6zig` is a hand-curated list over C++.