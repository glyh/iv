---
id: 001
title: How Zig binds libjpeg-turbo, and where setjmp lives
labels: [wayfinder:prototype]
status: open
assignee:
blocked_by: []
---

## Question

How does the Zig core call libjpeg-turbo, and where does libjpeg's error path
live?

`jpeglib.h` reports every failure through `jpeg_error_mgr.error_exit`, which
calls `exit()` unless a handler is installed. The conventional handler is
`longjmp`; Zig has no `setjmp`. So "which binding shape" is really "where the
C error machinery lives", and it sets the pattern for every later C dependency.

The routes:

1. **A thin C shim** — `src/core/decode/jpeg_shim.c`, compiled by Zig's clang
   with the recipe decision 10 documents. It owns `setjmp`, never lets a
   `longjmp` cross into Zig, and exposes an `iv_jpeg_decode(ptr, len, max_w,
   max_h, out)` returning an error enum. ADR 0003 already chose this shape for
   exiv2.
2. **`zig translate-c jpeglib.h`** plus a C `setjmp` trampoline. The whole
   header comes across as Zig — function-pointer structs, a variadic
   `error_exit` — and the trampoline is needed anyway.
3. **Hand-written `extern` declarations** — the same `setjmp` problem, with
   the struct layouts hand-maintained.

This is a prototype ticket, not a reading ticket: the resolution is the route
that decoded a committed fixture without a crash, with the build recipe written
next to the code that depends on it. If the shim wins, decision 10's
"`addTranslateC` plus `linkSystemLibrary`" default is amended (or an ADR
written) rather than quietly ignored.

## Done when

- The chosen route decodes a committed JPEG fixture and reports its dimensions
  and format.
- A deliberately broken JPEG comes back as an error value, not a crash and not
  an `exit()`.
- `build.zig` carries the include-path and linkage recipe as a comment
  (decision 10), and the cold build time is in the answer.
- The answer names the route and why, so tickets 003 and 010 can follow it.
