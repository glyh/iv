# iv

A Zig image viewer. The **core** - decode, transform, thumbnail, cache - is
Qt-free and testable without a display. The shell (Qt Widgets, with a
`QRhiWidget` viewport on Vulkan) is a later phase.

The architecture was decided before the first line of code. The decision records
are in `docs/design/`, the ADRs in `docs/adr/`, and the vocabulary in
`CONTEXT.md`.

## Build

```sh
zig build        # build
zig build test   # run the tests
zig build run    # run the placeholder CLI
```

Requires Zig 0.17.0.

## Layout

```
src/
  main.zig        the application entry point
  core/           the Qt-free core
    root.zig      the core's entry point
    bitmap.zig    the pixel type
    imageops.zig  scale, crop, flip, rotate, fitWithin
```
