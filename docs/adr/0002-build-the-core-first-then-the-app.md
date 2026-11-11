# Build the toolkit-free core first, then the app on top

Status: accepted

iv is built in two phases rather than as a UI application with pieces moved into
Zig over time. The reference implementation is a ~20k-line Qt widget tree over a
roughly 4-5k-line non-UI core (decode, transform, thumbnail, cache); building the
widget classes first would put 91 `Q_OBJECT` classes and moc on the critical path
for no runtime gain. So **phase 1** is a toolkit-free Zig core (`src/core/`) with
its own tests and no C++ of ours beyond the exiv2 shim (ADR 0003), and **phase 2**
builds the application on top
of it in Zig, with GTK4 as the shell.

## Boundary

The core is the pixel pipeline the earlier research named: decode -> transform
(scale/crop/rotate) -> thumbnail -> cache. Directory watching and video playback
stay out; they are shell concerns.

## Consequences

- The core's pixel type is the Zig `Bitmap`, not a toolkit image type; the shell
  boundary converts once, in phase 2.
- The core is usable and testable with no UI toolkit and no display.
- The reference implementation stays available for consultation; nothing in the
  core depends on it.