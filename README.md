# iv

A Zig image viewer. The **core** - decode, transform, thumbnail, cache - is
free of any UI toolkit and testable without a display. The shell (GTK4, with a
`GtkGLArea` viewport on OpenGL) is a later phase.

The architecture was decided before the first line of code. The decision records
are in `docs/design/`, the ADRs in `docs/adr/`, and the vocabulary in
`CONTEXT.md`.

## Build

`zig build` is the only build entry point: it generates the GTK bindings from
the GIR files on the machine and compiles everything in one invocation.

```sh
zig build                    # build
zig build test               # run the tests, no display needed
zig build run                # open the committed fixture
zig build run -Dfile=FILE    # open FILE
zig build check              # render a fixture under Xvfb and verify the pixels
```

Requirements: Zig 0.17.0, pkg-config, the GTK4 development files,
`gobject-introspection` (for `g-ir-generate`), libjpeg-turbo, libepoxy, and
`xvfb-run` for `zig build check`.

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
  core/           the toolkit-free core
    root.zig      the core's entry point
    bitmap.zig    the pixel type
    imageops.zig  scale, crop, flip, rotate, fitWithin
```
