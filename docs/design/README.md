# Design decisions

The technical choices behind iv, one document per decision. Start with
[00-overview.md](00-overview.md); each decision was grilled against concrete
options before it was written down. Decisions that
are hard to reverse and would surprise a later reader are also recorded as ADRs
in `../adr/`; the vocabulary they settle lives in `../../CONTEXT.md`.

| # | decision | status | doc |
|---|---|---|---|
| 01 | Core boundary: what the Zig core owns | decided | [01-core-boundary.md](01-core-boundary.md) |
| 02 | Core interface: requests + budget-driven scheduler | decided | [02-core-interface.md](02-core-interface.md) |
| 03 | Decode backends: registry dispatch | decided | [03-decode-backends.md](03-decode-backends.md) |
| 04 | Pixel format: 8-bit, straight alpha | decided | [04-pixel-format.md](04-pixel-format.md) |
| 05 | Colour management: lcms2 step, source preserved | decided | [05-colour-management.md](05-colour-management.md) |
| 06 | Scaling: area prefilter, then interpolate | decided | [06-scaling.md](06-scaling.md) |
| 07 | Cache: freedesktop disk contract + byte budget | decided | [07-cache.md](07-cache.md) |
| 08 | Concurrency: core-owned pool, step cancellation | decided | [08-concurrency.md](08-concurrency.md) |
| 09 | EXIF: exiv2 behind a C shim | decided | [09-exif-metadata.md](09-exif-metadata.md) |
| 10 | Dependencies: one build entry point | decided | [10-dependencies-build.md](10-dependencies-build.md) |
| 11 | Verification: simple unit tests (revised) | decided | [11-verification.md](11-verification.md) |
| 12 | Phase-2 UI: GTK4 + GtkGLArea (OpenGL) | decided | [12-ui-renderer.md](12-ui-renderer.md) |
| 13 | Repo: the Zig rewrite is its own repository | decided | [13-repo-strategy.md](13-repo-strategy.md) |
