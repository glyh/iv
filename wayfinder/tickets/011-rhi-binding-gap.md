---
id: 011
title: How the shell gets a QRhiWidget the binding does not have
labels: [wayfinder:grilling]
status: open
assignee:
blocked_by: []
---

## Question

Ticket 008 assumes `libqt6zig` binds `QRhiWidget`. It does not. The pinned
package (rev `76fbd35`, extracted at
`/tmp/lq6z/libqt6zig-6.8.2-OSXtXJRx…`) has **no** `QRhiWidget`,
`isDeviceLost` or `renderFailed` symbol anywhere under `include/` or
`src/`; the only RHI-shaped class it binds is Qt Quick's `QQuickRhiItem`,
which decision 12 rules out. The installed private header
(`/usr/include/qt6/QtWidgets/qrhiwidget.h`) is a declaration, not a bound
symbol.

So decision 12's viewport has no path through the binding the map pinned.
Settle how it gets one:

- **Generate the missing bindings.** libqt6zig is a generator; adding
  `QRhiWidget` may be a supported extension rather than a fork. Find out what
  its generator needs, and whether the result can still be a pinned URL+hash —
  the only dependency form Zig 0.17 accepts at build-script level.
- **Hand-written bindings plus one C++ translation unit.** `QRhiWidget` is
  subclassed to implement `initialize()` and `render()`, which means C++ of
  ours: exactly what ADR 0001 forbids ("no `Q_OBJECT`, no moc, no C++
  subclass of our own"). If that is the answer, ADR 0001 is amended or a new
  ADR records why, rather than being quietly broken.
- **Reopen decision 12 for the viewport only** — for example the
  `QGraphicsScene` fallback decision 12 already names as the replaceable
  alternative behind `Viewport` — keeping the Qt Widgets shell.

This is the first thing on the critical path that the thirteen design documents
do not already answer, and it blocks 008, which blocks the destination slice
009.
