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

## Licence

iv is free software: you can redistribute it and/or modify it under the terms
of the GNU General Public License as published by the Free Software Foundation,
either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details, in
[`LICENSE`](LICENSE).

Copyright (C) 2026 glyh.

## Layout

```
src/
  main.zig        the application entry point
  core/           the Qt-free core
    root.zig      the core's entry point
    bitmap.zig    the pixel type
    imageops.zig  scale, crop, flip, rotate, fitWithin
```
