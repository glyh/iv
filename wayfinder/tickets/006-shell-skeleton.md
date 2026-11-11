---
id: 006
title: Stand up the GTK4 shell skeleton
labels: [wayfinder:task]
status: open
assignee:
blocked_by: [004]
---

## Question

Land the smallest real shell: `zig build run -- <path>` starts a GTK4
application, opens a main window, and exits cleanly. No image yet - this ticket
is about the boundary, the dependency and the lifecycle, so ticket 008 has
somewhere to put a viewport.

- The build recipe from ticket 004: `addTranslateC` over a wrapper header, the
  include paths from `pkg-config --cflags-only-I gtk4`, and
  `exe.root_module.linkSystemLibrary("gtk-4", .{})` for the link flags.
- `iv` takes a path argument; the placeholder print in `src/main.zig` is
  replaced, not kept alongside.
- `gtk_init_check()` is checked, and a failure exits with a message instead of
  proceeding into a segfault.
- A smoke test that builds the window and returns. GTK4 has **no offscreen
  backend** (`GDK_BACKEND=offscreen` answers "No such backend"), so a test
  that needs a display runs under `xvfb-run` and is named as such; the rest of
  `zig build test` stays display-free.

## Done when

- `zig build run -- <any path>` opens a window in a real session and exits
  cleanly.
- The window-building smoke test passes under `xvfb-run`, and `zig build test`
  still passes with no display.