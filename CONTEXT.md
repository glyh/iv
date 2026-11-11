# iv

The vocabulary iv is designed in. This file is a glossary: it defines words, not
behaviour. Behaviour lives in `docs/design/`; decisions that are hard to reverse
live in `docs/adr/`.

## Language

**Core**:
The part of the program that turns a file or bytes into pixels, transforms them,
produces thumbnails and caches the results. It knows nothing about windows,
folders or settings.
_Avoid_: engine, library, backend

**Shell**:
Everything that is not the core: the user interface, directory listing and
watching, settings, video playback.
_Avoid_: frontend, app (ambiguous with the whole program)

**Backend**:
A module that claims one or more file formats and decodes them. A backend
recognises bytes, decodes them, or reports that the data is broken.
_Avoid_: decoder, plugin (a plugin implies runtime loading, which this is not)

**Pixel buffer**:
A buffer the core owns: a decoded frame, a colour-transformed copy, a scaled
copy. Pixel buffers are what the budget accounts for and what eviction removes.
_Avoid_: cache entry (one entry may hold several pixel buffers), artifact

**Budget**:
The user-set ceiling, in bytes, on everything the core holds: pixel buffers and the
in-flight buffers of work currently running.
_Avoid_: cache size (the budget covers more than the cache)

**Hint**:
The shell's statement that certain files are likely to be wanted next, in some
order. A hint is not a commitment; the core may ignore or drop it.
_Avoid_: request (a request is a commitment the core must answer)

**Results**:
The sequence of results one request may produce - typically a preview at a lower
resolution, then the final resolution. The shell renders each result as it
arrives.
_Avoid_: callback (too generic to be useful here), result stream

**GTK bindings**:
The `zig-gobject`-generated Zig modules the shell imports to call GTK (`gtk`,
`gdk`, `gio`, `glib`). They are generated at build time from the installed
GObject-introspection data, so they track the system's GTK.
_Avoid_: facade (there is no hand-written layer), wrapper

**Viewport**:
The shell's renderer: the part that takes a `Bitmap` and a target rectangle and
puts the pixels on screen. It is an interface, so the renderer can be replaced
without the core knowing which one runs.
_Avoid_: canvas, surface (a `GdkSurface` is GTK's, and is not this)
