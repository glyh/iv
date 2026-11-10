# On-disk thumbnails follow the freedesktop standard

Status: accepted

qimgv's private thumbnail directory has no freshness check, no size classes
and no eviction. The core implements the **freedesktop Thumbnail Managing
Standard** exactly: XDG cache classes 128/256/512/1024, the MD5 of the source
`file://` URI as the file name, `Thumb::MTime`/`Thumb::Size` freshness, atomic
rename for concurrent writers, and per-program failure entries. Full reasoning:
`../design/07-cache.md`.

## Consequences

- The cache is shared with the desktop's file managers, so the same image is not
  decoded twice, and eviction is the desktop ecosystem's problem.
- Nothing larger than 1024 is stored on disk; larger previews are derived in
  memory.
- The app's user-sizable thumbnail sizes map up to the next standard class and
  are downscaled in memory.
