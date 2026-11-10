# 07 - Cache

Status: decided.

## The question

The core has two caches with different pressures: thumbnails on disk, and
decoded frames in memory. What contract does each follow?

## 7a - On-disk thumbnails: the freedesktop standard (decided)

Adopt the **Thumbnail Managing Standard** exactly:

- `$XDG_CACHE_HOME/thumbnails/{normal,large,x-large,xx-large,fail}/`, sizes
  **128 / 256 / 512 / 1024** pixels.
- File name is the **MD5 of the canonical `file://` URI** plus `.png` - a hash
  of the *path*, not of the file's bytes.
- Permissions: directories 700, files 600.
- Freshness by comparing `Thumb::MTime` and `Thumb::Size` against the original;
  a global thumbnail without `Thumb::MTime` is an error and must be recreated.
- Concurrent writers write a temporary file in the same directory and
  **atomically rename** it into place.
- Failures are an empty PNG under `fail/<program>-<version>/`, with the same
  required keys.
- **Nothing larger than 1024 is stored on disk.** A bigger preview is derived in
  memory from the decoded source; the standard defines no such class, and
  inventing a private one would mean designing naming, freshness and eviction
  that the standard already gives away.

## Why

qimgv's private cache lacks all three of freshness, size classes and
eviction. Conforming fixes those at once, and buys something the private cache
can never have: **the file manager and the viewer share one thumbnail**, so the
same JPEG is not decoded twice, and the cache is reaped by the desktop
ecosystem instead of by an evictor we would have to write. Three conforming
implementations (nomacs, gwenview, PhotoQt) were read and can be copied from.

## 7b - In-memory accounting and eviction (decided)

- **Every pixel buffer the core retains counts** against the byte budget: the
  decoded source frame, colour-transformed copies, scaled copies, and the
  in-flight decode buffers.
- Eviction is **per pixel buffer**, least-recently-used, and pixel buffers currently
  used
  by an in-flight request are **pinned** and not evictable. Chromium's locked /
  unlocked decode cache is the model.
- A decoded source frame and its scaled copies therefore live and die
  independently, so a large derived copy cannot evict a source frame that another
  view still needs.

Why: bytes are what pressure the system, and "the source frame is expensive to
recreate while a scaled copy is cheap" is only exploitable when eviction is per
pixel buffer. Per-image accounting erases that difference; source-only accounting
understates real use.

## 7c - Mapping the app's thumbnail sizes onto the classes (decided)

- A request for size S uses the **smallest standard class >= S**, then downscales
  in memory. The spec explicitly allows serving a larger class and downscaling.
- A preview larger than 1024 is derived from the decoded source and never stored
  on disk (7a).
- The downscaled result is a pixel buffer under 7b's accounting and can be pinned.

Why: spec-sanctioned, maximises cache hits across the app's user-sizable sizes
and across applications, and the extra in-memory downscale is cheap and
cacheable.
