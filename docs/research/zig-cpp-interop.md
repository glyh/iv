# Zig <-> C++ interop: what Zig ships, what the ABI requires, what works here

Researched 2026-11 on this machine (Zig 0.17.0 / clang 22.1.8, gcc 16.2.1,
Qt 6.12.0). Every claim below was run, not recalled.

## The question

Does Zig ship its own C++ headers? Can `zig build` compile the one C++ unit the
core needs (the exiv2 shim)? What is the state of the art for Zig calling C++?

## Short answers

- **Yes, Zig ships a C++ standard library**: it bundles clang and libc++ (headers
  under `/usr/lib/zig/libcxx`), and `zig c++` *is* clang++. A program that uses
  only Zig's libc++ compiles with no extra flags.
- **But a C++ standard library is an ABI, not just headers.** Qt and exiv2 on
  this machine are built against **libstdc++** (`ldd /usr/lib/libQt6Core.so.6`
  shows `libstdc++.so.6`). `std::string`, `std::vector` and exceptions have
  different mangled names and layouts between libc++ and libstdc++, so a TU that
  talks to those libraries must use libstdc++ headers and link system libstdc++.
- **Zig has no C++ binding generator.** `@cImport` / translate-c is C only
  (Zig langref). Every C++ library is reached through a hand-written
  `extern "C"` shim. That is the state of the art in Zig today, and it is what
  libqt6zig does for all of Qt.

## The correction: the earlier "Zig cannot parse libstdc++" claim was wrong

We first recorded that Zig's clang 22 could not parse gcc 16's libstdc++ headers,
citing `/usr/include/c++/16/bits/std_abs.h: declaration conflicts with target of
using declaration already in scope`. That was an **include-path mistake, not a
clang-version limit**:

- **Failing form** - system C++ dirs passed with `-I`:
  `zig c++ -I/usr/include/c++/16 -I.../x86_64-pc-linux-gnu -I.../backward ...`
  With `-I` those headers land in the normal search path next to Zig's bundled
  libc++ headers, and the two standard libraries get mixed -> `std_abs.h`
  conflicts.
- **Working form** - the same dirs passed with `-isystem`:
  `zig c++ -isystem /usr/include/c++/16 -isystem .../x86_64-pc-linux-gnu
  -isystem .../backward -isystem /usr/lib/gcc/x86_64-pc-linux-gnu/16/include ...`

Verified after the correction:

- Five real qimgv TUs compile with `zig c++ -isystem ...`:
  `utils/imagefactory.cpp`, `sourcecontainers/imagestatic.cpp`,
  `sourcecontainers/documentinfo.cpp` (which includes exiv2),
  `components/cache/thumbnailcache.cpp`, `gui/customwidgets/thumbnailview.cpp`.
- A Qt program **compiles, links and runs** offscreen:
  `zig c++ -isystem ... $(pkg-config --cflags Qt6Widgets) main.cpp -o main
  $(pkg-config --libs Qt6Widgets)` -> exit 0.
- `zig c++`'s default include path is Zig's own libc++
  (`/usr/lib/zig/libcxx/include`), which is exactly why the mix happens.

## The linkage rule

The program must not pull libc++ in. libqt6zig's own recipe is the reference
(`exports.zig` / `build.zig`): `link_libcpp = false`, then locate the system
runtime with `gcc --print-file-name=libstdc++.so.6` and add it as an object
file; its C++ glue compiles with `-nostdinc++ -nostdlib++` and its own
`libq20type_traits` shim. For code that includes Qt/exiv2 headers, the working
form is the `-isystem` recipe above plus system libstdc++ at link time.

## Patterns that work (and one that does not exist)

1. **`extern "C"` shim** - the universal pattern: a thin C++ file exports plain C
   functions; Zig sees only that C header. This is what the port already does
   (`qzimage`, and now the exiv2 shim).
2. **Match the stdlib and the ABI** - libstdc++ with libstdc++ libraries. This is
   the rule that decides everything else.
3. **`-fno-exceptions -fno-rtti`** where the API allows it - shrinks the boundary
   and removes the unwinding hazard, at the cost of not calling APIs that throw.
   exiv2 throws, so the shim must catch at the boundary instead.
4. **No automatic C++ binding** - unlike Rust's `cxx`, there is no Zig tool that
   generates bindings from C++ headers; hand-written shims are the method.

## What this means for the port

- The exiv2 shim **can be compiled by `zig build` itself**; the "second
  compiler" cost that decision 09 assumed largely disappears.
- The recipe is include-path sensitive and must be documented, not rediscovered:
  `-isystem` (never `-I`) for system C++ headers, and never link libc++ into a
  libstdc++ program.
- Residual risk: Zig's clang is pinned to a libstdc++ it can parse. A future gcc
  could break it; the fallbacks are the system clang (23.1.4 is installed here)
  or a separate build step for the shim. That is decision 10's remaining fork.
