---
id: 006
title: Stand up the Qt Widgets shell skeleton
labels: [wayfinder:task]
status: open
assignee:
blocked_by: [004]
---

## Question

Land the smallest real shell: `zig build run -- <path>` starts a Qt Widgets
application, opens a main window, and exits cleanly. No image yet — this ticket
is about the boundary, the dependency and the lifecycle, so ticket 008 has
somewhere to put a viewport.

- `libqt6zig` pinned per ticket 004, linking only the Qt classes actually
  used.
- `iv` takes a path argument; the placeholder print in `src/main.zig` is
  replaced, not kept alongside.
- An offscreen smoke test (`QT_QPA_PLATFORM=offscreen`) that builds the
  window and returns, so the test step stays display-free.
- The exception rule from ticket 004 applies from the first call site rather
  than being retrofitted.

## Done when

- `zig build run -- <any path>` opens a window in a real session and exits
  cleanly.
- The offscreen smoke test passes under `zig build test`, with no display and
  no Qt Quick.
