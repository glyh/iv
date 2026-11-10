---
id: 004
title: The Zig-Qt boundary and the shell's shape
labels: [wayfinder:grilling]
status: open
assignee:
blocked_by: []
---

## Question

Decision 12 chose Qt Widgets, and `docs/research/libqt6zig.md` shows the
binding works on this toolchain (Zig 0.17.0, Qt 6.12.0). That research also
names two costs that have to become rules before any shell code exists:

- The binding compiles each Qt class's C++ glue, and its flags are only
  `-nostdinc++ -nostdlib++`: `-fno-exceptions` is **not** used. A C++
  exception unwinding through `extern "C"` into a Zig frame is undefined
  behaviour.
- It must be consumed as a pinned URL+hash dependency (rev `76fbd35`), not as
  a vendored path; a local `.path` dependency fails at build-script level.

Settle:

- Which module owns every Qt call, and what rule keeps a throwing Qt API out of
  the Zig call graph — a wrapper per entry point, or a reviewed allow-list.
- Where the `Viewport` seam sits (decision 12) and what crosses it. The plan:
  the core hands out a `Bitmap`, and the shell hands nothing back into the
  core.
- How the shell keeps "every event has exactly one consumer" (ADR 0001) across
  the binding, including the worker-to-main-thread hop.
- The layout under `src/shell/` and the `QApplication` lifecycle: who owns
  it and what ends the event loop.

## Done when

- The rules are written where the shell code will live, not only in this
  ticket.
- Any term the shell introduces is in `CONTEXT.md`, or is a word the glossary
  already defines.
