---
id: 004
title: The Zig-GTK boundary and the shell's shape
labels: [wayfinder:grilling]
status: open
assignee:
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