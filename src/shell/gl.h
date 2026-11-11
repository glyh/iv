// The GL entry points, via libepoxy. GTK links libepoxy already, and
// zig-gobject has no GL module (its GL-1.0 typelib is a stub with no
// functions). See docs/research/mvp-reachability.md.
#include <epoxy/gl.h>
