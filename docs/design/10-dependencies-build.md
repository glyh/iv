# 10 - Dependencies and build policy: one build entry point

Status: decided

## The question

How are dependencies declared, and who compiles the core's one C++ unit?

## Context

- The decode backends and the colour engine are C libraries (libjpeg-turbo,
  libpng, libwebp, `stb_image`, lcms2, ...). Zig can compile those itself
  through `translate-c`.
- The exiv2 shim is the core's single C++ translation unit (decision 09).
- Zig ships clang and libc++, but Qt and exiv2 are **libstdc++** libraries, so
  the shim must compile against system libstdc++ headers and link system
  libstdc++. The verified recipe is in `../research/zig-cpp-interop.md`.

## The options

1. `zig build` only; Zig's own clang compiles the shim with the documented
   recipe.
2. The system C++ compiler compiles the shim through an `addSystemCommand`
   step, as a C++ project normally would.
3. No C++ at all - which means revisiting decision 09.

## Decision

**Option 1. `zig build` is the only build entry point.**

- C libraries are declared with `addTranslateC` plus `linkSystemLibrary`
  (which resolves through pkg-config), or vendored when they are single-header
  (`stb_image`).
- The exiv2 shim is compiled by **Zig's own clang**, with:
  - the system C++ include directories passed as `-isystem` - **never `-I`**,
    which mixes them with Zig's bundled libc++ and produces the
    `bits/std_abs.h` conflict;
  - `link_libcpp = false` on the module, and the system libstdc++ linked.
- That recipe is documented in `build.zig` next to the code that depends on it,
  so it is not rediscovered by the next person.
- Optional backends (tiers 2 and 3 from decision 03) are `-D` build options,
  in the spirit of the optional-dependency flags a Qt build uses.

## Fallback, not default

If a future libstdc++ stops being parseable by Zig's bundled clang, the shim
moves to the system C++ compiler behind an `addSystemCommand` step (option 2).
That is a one-file change, which is why depending on option 1 now is acceptable.

## Consequences

- The core's build requirements are: Zig, pkg-config for C libraries, a system
  libstdc++ at link time, and whichever optional backends are enabled.
- `build.zig.zon` stays empty for the core: libqt6zig is a dependency of the
  phase-2 application, not of the core.
- Cross-compilation is bounded by the same libstdc++ requirement as any C++
  program - the core is not "pure Zig, builds anywhere".
