# Image viewer core: state of the art, read before porting

Written before porting qimgv's core to Zig, to pin down what "good" looks like
instead of porting the current shape by default.

**Method.** This environment's plain web fetch was broken all session (every
hostname resolved to a non-public IP), and the delegated research agents failed
four times for the same reason, so the reading below was done directly through
two channels that work here: **passenger** (a real Chrome, for specs and doc
sites) and **the GitHub API** (for repo READMEs and source). Every claim cites
the source that owns it. Nothing was benchmarked here; numbers are quoted and
attributed, and the fork's own measurements are labelled as such.

## The baseline: qimgv's core today

| area | today | where |
|---|---|---|
| decode | QImageReader (Qt), per-format plugins | `qimgv/sourcecontainers/imagestatic.cpp`, `qimgv/sourcecontainers/documentinfo.h` |
| decode-time downscale | already used for thumbnails: `QImageReader::setScaledSize()` before `read()` | `research/thumbnail-cache-standard` branch, `components/thumbnailer/thumbnailerrunnable.cpp:103,186` |
| scale/transform | Qt smooth scale, optional OpenCV | `qimgv/utils/imagelib.{h,cpp}` |
| cache | flat directory of PNGs named by an opaque id; no mtime check, no size classes, no eviction | `research/thumbnail-cache-standard` branch, `components/cache/thumbnailcache.cpp:4,8` |
| concurrency | QThread/QThreadPool + Qt signals; scaler uses `Qt::QueuedConnection` | `qimgv/components/{scaler,thumbnailer,loader}` |
| render | `QGraphicsView` with two pixmap items (`pixmapItem`/`pixmapItemScaled`) | `research/qt-renderer-frontier` branch |

Component sizes as measured here: `components/directorymanager` 1709 LOC/10
Q_OBJECT, `sourcecontainers` 1064 LOC/QImage-heavy, `components/thumbnailer`
322, `components/scaler` 245, `components/cache` 223,
`components/loader` 126. All of it is threaded Qt; none of it is testable
without Qt today.

## 1. Decode layer

- **libjpeg-turbo** - SIMD-accelerated baseline *and* progressive JPEG; colour
  space extensions for 32-bit formats (BGRA/RGBX/...); **IDCT scaling** in the
  decompressor with factors from 1/8 to 1/1, some SIMD-accelerated; SmartScale
  for better small decodes.
  [README](https://github.com/libjpeg-turbo/libjpeg-turbo#readme)
- **jpegli** - Google's newer JPEG encoder/decoder, **API and ABI compatible
  with libjpeg62** (drop-in `libjpeg.so.62`); quality set by a JPEG-XL-style
  distance parameter; has ICC/XYB-specific handling.
  [README](https://github.com/google/jpegli#readme)
- **libjxl** - JPEG XL, ISO/IEC 18181-1; the format is built for **progressive
  decoding and partial decoding of a region of interest**, with progressive
  previews across channels.
  [format_overview](https://github.com/libjxl/libjxl/blob/main/doc/format_overview.md)
  Its colour doc argues transfer functions should be **parametric, not LUTs**,
  and that ICC v2/v4 cannot carry HDR transfer functions accurately - so it
  expects to move away from ICC. [color_management](https://github.com/libjxl/libjxl/blob/main/doc/color_management.md)
- **libavif** - portable **C** AVIF; all AV1 YUV formats and bit depths incl.
  alpha; decoder backends are separate (dav1d, libgav1, libaom...); optional
  libyuv. [README](https://github.com/AOMediaCodec/libavif#readme)
- **libwebp** - WebP v1.6.0, images and animations.
  [README](https://github.com/webmproject/libwebp#readme)
- **libheif** - HDR with per-profile colour transform; region annotations and
  masks; **streaming through a data-reader interface**; optional parallel tile
  decode; libsharpyuv for YCbCr/RGB. [README](https://github.com/strukturag/libheif#readme)
- **libvips** - the reference demand-driven, threaded pipeline; many formats
  through loaders; ICC import/export/transform; SIMD; UltraHDR.
  [README](https://github.com/libvips/libvips#readme)
- **gdk-pixbuf** (GTK) - PNG/JPEG/TIFF built in plus pluggable loader modules.
  [README](https://github.com/GNOME/gdk-pixbuf#readme)
- **kimageformats** (Qt) - `QImage` plugins for AVIF, HEIF, JXL, EXR, XCF,
  camera RAW and more; what Qt viewers bolt on for modern formats.
  [README](https://github.com/KDE/kimageformats#readme)

**Decode-time downscaling and partial decode are the levers** that avoid the
full-size bitmap: TurboJPEG's scaling factors, libjxl's progressive/ROI,
libheif's tiles. The fork's thumbnailer already exploits the first through Qt,
so a Zig core's decode API should take a max size (and later a region) from the
start.

**EXIF.** ADR 0003 chose an exiv2 C++ shim. **libexif is plain C, needs no other
library, covers all EXIF 2.1 tags and most 2.2**, but its own README says maker
notes are only partly handled ("not very well").
[README](https://github.com/libexif/libexif#readme) gthumb uses exiv2
([gthumb README](https://github.com/GNOME/gthumb#readme)); the C viewers use
libexif. The trade is exiv2's metadata depth against keeping the core free of
C++.

**Not verified:** hardware still-image decode (VA-API/NVDEC). No first-party
evidence was found that it is a usable path for a desktop viewer.

## 2. Scaling and colour

- **libyuv** - C; YUV scaling and conversion: point/bilinear/box filters,
  YUV<->RGB conversion, rotate 90/180/270.
  [README](https://github.com/lemenkov/libyuv#readme) (mirror; canonical is
  chromium.googlesource.com). Useful if a YUV path ever appears; for RGB work
  Zig's own vectors are enough.
- **Highway** - portable C++ SIMD, with a published evaluation calling it the
  most suitable SIMD library in its comparison.
  [README](https://github.com/google/highway#readme) C++, so not directly usable
  from a Qt-free Zig core.
- **Zig** - `@Vector` and `std.simd` cover bilinear/bicubic kernels without
  a dependency; a windowed-sinc filter is more work but still self-contained.
- **Skia's colour model** is the clearest statement of what colour management
  actually is: every space describes a transform to/from **XYZ D50**, and a
  managed draw is six steps - unpremultiply, linearize, 3x3 to XYZ D50, 3x3 to
  the destination gamut, encode, premultiply - implemented as
  `SkColorSpaceXformSteps`. [Skia color](https://skia.org/docs/user/color/)
- **lcms2** is the C colour engine to build on: a full ICC 4.4 implementation
  covering V2/V4 profile kinds.
  [README](https://github.com/mm2/Little-CMS#readme)
- **GPU scaling** is a phase-2 UI concern, not core: the fork's renderer survey
  found the one modern path in the family is Wynpix's single QRhi item with
  **mipmaps and trilinear sampling**, a **TileGrid** past the texture limit, a
  GPU filter set, HDR tone mapping, and an off-thread ICC LUT.
  [qt-renderer-frontier](qt-renderer-frontier.md)

## 3. Cache, memory, thumbnails, concurrency

- **On-disk thumbnails have a standard, and the fork does not follow it.** The
  freedesktop **Thumbnail Managing Standard** (v0.9.0, Dec 2020 added x-large
  and xx-large) fixes, in its own words:
  - one directory per user, `$XDG_CACHE_HOME/thumbnails/` with
    `normal/` (<=128x128), `large/` (256x256), `x-large/` (512x512),
    `xx-large/` (1024x1024) and `fail/`;
  - the name is **MD5 of the canonical `file://` URI - not of the file** -
    plus `.png`; a flat 36-character filename;
  - permissions: directories 700, files 600;
  - **freshness** by comparing `Thumb::MTime` and `Thumb::Size` against the
    file; a missing `Thumb::MTime` on a global thumbnail is an error;
  - concurrent writers use a temp file in the same directory plus an **atomic
    rename**;
  - failures are an **empty PNG per program** under `fail/<program>-<version>/`
    with the same required keys;
  - deletion belongs to a file manager or a cache daemon; local files are
    deleted when the original is gone, remote schemes after a timeout.

  [directory](https://specifications.freedesktop.org/thumbnail/latest/directory.html),
  [thumbsave](https://specifications.freedesktop.org/thumbnail/latest/thumbsave.html),
  [modifications](https://specifications.freedesktop.org/thumbnail/latest/modifications.html),
  [failures](https://specifications.freedesktop.org/thumbnail/latest/failures.html),
  [delete](https://specifications.freedesktop.org/thumbnail/latest/delete.html)
  The fork's earlier note read three conforming implementations (nomacs,
  gwenview, PhotoQt); qimgv, qView, pineapple-pictures and lximage-qt are the
  outliers. [thumbnail-cache-standard](thumbnail-cache-standard.md)
- **Cheap ideas from nomacs**: a cache safe from any thread, background
  `cleanupAsync()` reaping, serving a larger class and downscaling on the
  spot, and disabling the cache for the session on a filesystem error.
- **Demand-driven decode with a lock, done at scale**: Chromium's
  `ImageDecodeCache` generates decode tasks, decodes, stores in a cache,
  returns a locked image, and can decode "at raster" when it is too late to wait
  (`TaskResult{is_at_raster_decode}`).
  [image_decode_cache.h](https://github.com/chromium/chromium/blob/main/cc/tiles/image_decode_cache.h)
  That is the shape of a bounded, budgeted in-memory cache for a viewer too.
- **Large images**: TileGrid plus mipmaps (Wynpix), or a tile pyramid for
  gigapixel inputs; libvips is the mature pull architecture.
- **Concurrency that changes feel** (all from the renderer survey, in Wynpix): a
  **navigation throttle** that defers a step following the previous by less than
  ~66 ms so a held key costs one decode; a **preview** of the next file's
  uncropped thumbnail while the real load is deferred; an **image preparer**
  that decodes off the GUI thread for CPU actions.
- **Budget to beat**: qimgv idle 72 MB RSS, 140.8 MB on a 5 000-image folder
  with 14 threads; Qt Widgets itself 44 MB empty.
  [gui-stack-weight](gui-stack-weight.md)
- **Zig 0.17 gives the concurrency substrate**: `std.Thread.spawn`, and a new
  `std.Io` with structured concurrency (`Group.async`/`await`,
  **`Cancelable`** cancellation, `Semaphore`, `RwLock`, `Mutex`). Per-image
  cancellation is first-class, which is what a viewer's "user moved on" case
  needs.

## 4. The reference family, and what actually differs

Read directly (README/source) plus the renderer survey:

| viewer | core shape |
|---|---|
| **imv** | C, SDL2; a **backend plugin interface** (`imv_backend` with `open_path`/`open_memory` returning SUCCESS/BAD_PATH/UNSUPPORTED) with per-library backends: freeimage, libheif, libjpeg, libnsgif, libpng, librsvg, libtiff; chosen at build time. [backend.h](https://github.com/eXeC64/imv/blob/master/src/backend.h) |
| nsxiv | C, Imlib2 1.11+; libexif for auto-orientation and EXIF thumbnails; thumbnail cache |
| feh | C, Imlib2, libpng, X11; optional libexif |
| pqiv | GTK3, gdk-pixbuf (+libwebp, ffmpeg); **caches zoomed copies**, preloads the next image in the background |
| nomacs | Qt widgets, QGraphicsView + QtConcurrent; kimageformats for AVIF/HEIF/JXL; threaded thumbnail cache |
| qView | Qt, QGraphicsView; minimal |
| gwenview | Qt/KDE; own raster items; kimageformats; XDG-conformant thumbnails |
| gthumb | GTK, gdk-pixbuf libs; PNG/JPEG/WEBP/SVG/JXL/HEIF/AVIF/TIFF/GIF/RAW; exiv2; libjxl |
| PhotoQt | Qt Quick; no custom RHI node found |
| Wynpix | Qt Quick + QRhi; the renderer frontier |
| qimgv | Qt, QGraphicsView; private thumbnail dir; full decode then CPU scale on zoom |

The pattern: **decode always comes from a C library**, usually through a toolkit
loader or a per-format backend; scaling is usually CPU and re-run per zoom step;
the viewers that feel fast differ in **cache contract, prefetch, and
decode-time downscaling**, not in their scaler.

## 5. What this implies for a Qt-free Zig core

1. **Currency**: an explicit bitmap (done: `Bitmap`), 8-bit gray/RGB/RGBA
   first; 16-bit/HDR later, and if HDR matters, prefer a parametric
   transfer-function design over ICC (libjxl's argument).
2. **Decode**: C libraries behind translate-c, dispatched on magic bytes - an
   imv-style backend table is a good shape - with a max-size (and later region)
   argument on the API. JPEG first (libjpeg-turbo), then PNG, WebP, AVIF
   (dav1d), JXL, HEIF; jpegli is a drop-in substitution later if its quality
   claim holds.
3. **EXIF**: libexif (plain C) if its tag coverage suffices; exiv2 via a C shim
   only if maker-note depth is needed. That trade was decided in favour of
   exiv2: `docs/design/09-exif-metadata.md`, ADR 0003.
4. **Scale/transform**: Zig `std.simd`/`@Vector` kernels, filter selectable so
   a GPU path can replace it in phase 2; libyuv only if a YUV path appears.
5. **Colour**: lcms2 through translate-c, one defined working space, transform
   once per image; keep the Skia six-step model in mind as the definition of
   correctness.
6. **Cache**: implement the freedesktop contract exactly (classes, URI+MD5,
   Thumb::URI/Thumb::MTime, atomic rename, fail dir) for the disk cache, and a
   separate budgeted in-memory cache with Chromium's task/lock shape.
7. **Concurrency**: `std.Io` structured concurrency with `Cancelable` per
   request, plus the three feel features - navigation throttle, next-image
   preview, off-thread prepare.
8. **Verification**: keep differential pixel tests against the C++ implementation
   while it still builds; that is what the C ABI bridge is for.

The one thing this survey argues against is copying qimgv's "full decode, then
CPU scale on every zoom step". Every fast viewer avoids re-decoding, and where
it can, re-scaling - through decode-time downscale, a cached scaled copy, or
mipmapped sampling.

## Gaps

- **Hardware still-image decode** was not established either way.
- Chromium's **discardable-memory** mechanics were not read (only the
  `ImageDecodeCache` interface).
- **Qt's own colour internals** (`QColorSpace`/`QImage` managed drawing) were
  not read, so "Qt parity" here means behaviour, not implementation.
- No independent benchmarks; the fork's GPU rows were measured under software
  rendering (Xvfb/llvmpipe), so they are not hardware numbers.
- libexif vs exiv2 maker-note coverage was not compared tag by tag.
