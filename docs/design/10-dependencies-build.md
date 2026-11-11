# 10 - Dependencies and build policy: one build entry point

Status: decided

## The question

How are dependencies declared, and who compiles the core's one C++ unit?

## Context

- The decode backends and the colour engine are C libraries (libjpeg-turbo,
  libpng, libwebp, `stb_image`, lcms2, ...). Zig compiles those itself through
  `translate-c`.
- The shell's toolkit is **GTK4**, also a C library, but reached through
  **`zig-gobject`** rather than `translate-c` (decision 12): a pinned Zig
  package whose generator runs as a build step over the installed GIR files.
- The exiv2 shim is the core's single C++ translation unit (decision 09).
- Zig ships clang and libc++, but exiv2 is a **libstdc++** library, so the shim
  must compile against system libstdc++ headers and link system libstdc++. The
  verified recipe is in `../research/zig-cpp-interop.md`.
- On Zig 0.17 **`@cImport` no longer exists**; `translate-c`, driven from
  `build.zig`, is the mechanism for C libraries.

## The options

1. `zig build` only; Zig's own clang compiles the shim with the documented
   recipe.
2. The system C++ compiler compiles the shim through an `addSystemCommand`
   step, as a C++ project normally would.
3. No C++ at all - which means revisiting decision 09.

## Decision

**Option 1. `zig build` is the only build entry point.**

- C libraries are declared with `addTranslateC` plus `linkSystemLibrary`, or
  vendored when they are single-header (`stb_image`). The two halves are
  separate steps: `linkSystemLibrary` supplies the link flags, and the include
  paths must be added explicitly from `pkg-config --cflags-only-I gtk4` -
  without them translation fails with `'gtk/gtk.h' not found`.
- **GTK4 is the exception to that route.** The shell reaches it through
  `zig-gobject`, whose generator runs as a build step and emits a bindings
  package from the installed GIR files. That step needs `gobject-introspection`
  and the GIR XML for GTK's closure; on this machine `cairo-1.0.gir` and
  `freetype2-2.0.gir` are not installed and are regenerated from their
  typelibs. The measured recipe is in `../research/zig-gobject.md`.
- On Zig 0.17 the API is not the shape older documentation shows:
  `linkSystemLibrary` is a **module** method
  (`exe.root_module.linkSystemLibrary("gtk-4", .{})`), not a compile-step
  method, and `TranslateC` carries its own `addIncludePath` and
  `linkSystemLibrary`. The working recipe is in
  `../research/gtk4-zig-interop.md`.
- **No hand-written binding layer.** For the core's C libraries, a function
  the installed headers declare is callable. For GTK4 the binding is generated,
  not written here, and the only thing iv maintains is the pinned revision.
- The exiv2 shim is compiled by **Zig's own clang**, with:
  - the system C++ include directories passed as `-isystem` - **never `-I`**,
    which mixes them with Zig's bundled libc++ and produces the
    `bits/std_abs.h` conflict;
  - `link_libcpp = false` on the module, and the system libstdc++ linked.
- That recipe is documented in `build.zig` next to the code that depends on it,
  so it is not rediscovered by the next person.
- Optional backends (tiers 2 and 3 from decision 03) are `-D` build options, in
  the spirit of the optional-dependency flags the reference viewer's build
  uses.

## Fallback, not default

If a future libstdc++ stops being parseable by Zig's bundled clang, the shim
moves to the system C++ compiler behind an `addSystemCommand` step (option 2).
That is a one-file change, which is why depending on option 1 now is acceptable.

## Consequences

- The build requirements are: Zig, pkg-config for the C libraries, a system
  libstdc++ at link time, and whichever optional backends are enabled. The
  phase-2 application adds `gobject-introspection` and the GIR files, because
  its GTK bindings are generated at build time.
- **`build.zig.zon` pins `zig-gobject`** (and its `xml` dependency); every
  other dependency is a system library resolved through pkg-config. GTK4 is a
  phase-2 dependency, not a core one.
- Cross-compilation is bounded by the same libstdc++ requirement as any C++
  program - the core is not "pure Zig, builds anywhere".