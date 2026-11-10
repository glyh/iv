# iv in one page

iv is built in two phases: a Qt-free Zig **core** first, then the application
rebuilt on top of it. This folder holds one document per decision; this page is
the map, and `README.md` is the index.

## Shape

- **Core** ([01](01-core-boundary.md)): the pixel pipeline only - decode,
  transform, thumbnail, cache. Directories, settings, video and UI are the
  **shell**.
- **Interface** ([02](02-core-interface.md)): requests from the shell plus a
  budget-aware scheduler in the core. A user-set **byte budget** decides lazy
  versus eager, and one request may yield several results over time (preview,
  then final).
- **Decode** ([03](03-decode-backends.md)): a registry of backends, one module per
  library; still images only; three dependency tiers.
- **Pixels** ([04](04-pixel-format.md)): 8-bit gray/RGB/RGBA, straight alpha,
  premultiply inside the resampler.
- **Colour** ([05](05-colour-management.md)): an lcms2 transform step that is a
  no-op when source and destination agree; source pixels and profile preserved.
- **Scaling** ([06](06-scaling.md)): area prefilter above 2x, bicubic otherwise,
  Zig `@Vector` kernels.
- **Cache** ([07](07-cache.md)): the freedesktop thumbnail contract on disk, a
  byte-budgeted per-pixel-buffer LRU in memory.
- **Concurrency** ([08](08-concurrency.md)): a core-owned fixed pool, two
  priority bands, step-boundary cancellation.
- **EXIF** ([09](09-exif-metadata.md)): exiv2 behind a C shim - the one C++ unit
  in the core.
- **Build** ([10](10-dependencies-build.md)): one `zig build` entry point; Zig's
  clang compiles the shim.
- **Verification** ([11](11-verification.md)): unit tests only; the differential
  harness is optional.
- **UI** ([12](12-ui-renderer.md)): a Qt Widgets shell; the viewport is a
  `QRhiWidget` on Vulkan.
- **Repo** ([13](13-repo-strategy.md)): iv is its own repository; qimgv is a reference.

## Reading order

01 -> 02 -> 03 -> 04 -> 05 -> 06 -> 07 -> 08 -> 09 -> 10 -> 11 -> 12 -> 13.
The first ten are the core; 12 is the application; 11 and 13 are cross-cutting.

## Where the rest lives

- Vocabulary: `../../CONTEXT.md`
- The hard-to-reverse decisions, restated with their trade-offs: `../adr/`
- The evidence behind them: `../research/`
