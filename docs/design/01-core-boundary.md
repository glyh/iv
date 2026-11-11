# 01 - Core boundary: the pixel pipeline only

Status: decided (grilled 2026-11)

## The question

Which jobs belong to the Zig core and which to the application shell?

## The options

1. **Pixel pipeline only** - decode a file to pixels, rotate/scale/crop, produce
   thumbnails, cache results. Directories, settings, video and all UI stay in
   the shell.
2. **Pipeline + directory scanning/watching** - the core also walks folders and
   reports when files appear or change.
3. **Everything non-visual** - pipeline + directories + EXIF metadata + video
   playback control.

## Decision

**Pixel pipeline only.** The core turns a file (or bytes) into pixels, transforms
them, produces thumbnails, and caches results. It knows nothing about folders,
settings, video, or windows.

## Why

- The smallest surface that still contains all the expensive work, so it can be
  unit-tested with no GUI and no platform watchers.
- Directory watching is platform and policy: inotify on Linux, kqueue on BSD,
  ReadDirectoryChangesW on Windows, plus polling fallbacks, plus "what counts as
  a new file" rules. That churns with the shell's needs and GIO provides it
  (GFileMonitor).
- It matches what the earlier research on qimgv called the core (decode ->
  scale -> thumbnail -> cache), so the boundary is not invented here.
- The pieces excluded will still be ported later; they just do not have to be
  correct before the first image can be decoded.

## Consequences

- The shell keeps owning file listing and watching. On Linux the shell will use
  GFileMonitor plus a worker thread; it is not the Zig core's problem.
- EXIF orientation is a *decode* concern (a rotated photo must come out upright),
  so metadata enters the core at least for orientation. Where the rest of EXIF
  lives is decision 09.
- Video and the mpv plugin stay entirely in the shell.
- The core has no dependency on a UI toolkit by construction.
