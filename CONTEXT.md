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

**Artifact**:
Any pixel buffer the core retains: a decoded frame, a colour-transformed copy, a
scaled copy. Artifacts are what the budget accounts for and what eviction
removes.
_Avoid_: cache entry (one entry may hold several artifacts)

**Budget**:
The user-set ceiling, in bytes, on everything the core holds: artifacts and the
in-flight buffers of work currently running.
_Avoid_: cache size (the budget covers more than the cache)

**Hint**:
The shell's statement that certain files are likely to be wanted next, in some
order. A hint is not a commitment; the core may ignore or drop it.
_Avoid_: request (a request is a commitment the core must answer)

**Result stream**:
The sequence of results one request may produce - typically a preview at a lower
resolution, then the final resolution. The shell renders each result as it
arrives.
_Avoid_: callback (too generic to be useful here)
