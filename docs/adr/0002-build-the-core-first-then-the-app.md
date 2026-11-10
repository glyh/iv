# Build the Qt-free core first, then the app on top

Status: accepted

iv is built in two phases rather than as a Qt application with pieces moved into
Zig over time. The reference implementation is a ~20k-line Qt widget tree over a
roughly 4-5k-line non-UI core (decode, transform, thumbnail, cache); building the
widget classes first would put 91 `Q_OBJECT` classes and moc on the critical path
for no runtime gain. So **phase 1** is a Qt-free Zig core (`src/core/`) with its
own tests and no C++ of ours, and **phase 2** builds the application on top of it
in Zig, with Qt Widgets as the shell.

## Boundary

The core is the pixel pipeline the earlier research named: decode -> transform
(scale/crop/rotate) -> thumbnail -> cache. Directory watching and video playback
stay out; they are shell concerns.

## Consequences

- The core's currency is the Zig `Bitmap`, not `QImage`; the Qt boundary converts
  once, in phase 2.
- The core is usable and testable with no Qt and no display.
- The reference implementation stays available for consultation; nothing in the
  core depends on it.
