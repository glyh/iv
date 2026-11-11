#!/bin/sh
# Regenerate the two GIR files this machine does not ship.
#
# Gtk-4.0.gir depends on cairo-1.0 and freetype2-2.0, and the cairo and
# freetype2 packages install only their typelibs - no XML. `g-ir-generate`
# (gobject-introspection) turns a typelib back into the XML the binding
# generator needs.
#
# Used by build/bindings.zig: $1 is the output directory.
set -eu

out=$1
typelibs=$(pkg-config --variable=typelibdir gobject-introspection-1.0)

mkdir -p "$out"
g-ir-generate "$typelibs/cairo-1.0.typelib" > "$out/cairo-1.0.gir"
g-ir-generate "$typelibs/freetype2-2.0.typelib" > "$out/freetype2-2.0.gir"