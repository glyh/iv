# MVP reachability: every component the first image needs

Spiked 2026-11-11 on this machine (Zig 0.17.0, GTK 4.24.1, libjpeg 3.2.1,
libepoxy 1.5.10). Every row below was run. The probe projects are throwaway and
live under `/tmp`; this document is the record.

## The path

`iv <path>` needs a window, a GL viewport in it, the file decoded to pixels,
those pixels on a texture, a shader that samples it, and a quad. Two of those
were not obviously reachable, so each was spiked separately before the whole
path was run.

## 1. GL entry points: not in zig-gobject, but libepoxy works

`zig-gobject` has no `GL-1.0` module, and the reason is that the only `GL-1.0`
data installed here is a **stub typelib**:

```
$ g-ir-generate /usr/lib/girepository-1.0/GL-1.0.typelib | wc -l
26
$ grep -c 'glGenTextures' /tmp/girs/GL-1.0.gir
0
```

It declares two records and no functions, so GL cannot be bound through
GObject-introspection on this machine.

**The route that works: `translate-c` over `epoxy/gl.h`, linking `libepoxy`.**
libepoxy is the GL dispatch library GTK itself links, and it exists for this.

```
$ zig translate-c $(pkg-config --cflags-only-I epoxy) /tmp/gl_wrap.h
exit 0, 24,318 lines of Zig
```

translate-c turns each GL name into an inline wrapper over libepoxy's function
pointer:

```zig
pub extern var epoxy_glGenTextures: ?*const fn (n: GLsizei, textures: [*c]GLuint) callconv(.c) void;
pub inline fn glGenTextures(n: GLsizei, textures: [*c]GLuint) void {
    return epoxy_glGenTextures.?(n, textures);
}
```

So `gl.glGenTextures(...)` is called directly; no hand-written declarations.

## 2. The whole path, end to end

A probe at `/tmp/mvpspike` does all of it under `xvfb-run`:

```
decoded 600x640 rgba
GL_VERSION = OpenGL ES 3.2 Mesa 26.2.6-arch1.1
texture width 600 (expected 600)
shader compiled ok
shader compiled ok
program linked: true
viewport 954x1038; centre rendered = { 4, 3, 35, 255 }; image centre = { 24, 28, 73, 255 }
exit 0
```

That is decode to RGBA, `glTexImage2D`, a compiled and linked GLSL ES 300
vertex/fragment pair, a textured quad, and `glReadPixels`. The rendered centre
is in the image's colour neighbourhood rather than black or flat. It is not
bit-exact because the quad stretches a 600x640 image over a 954x1038 viewport
with `GL_LINEAR` filtering, so the centre sample blends neighbouring texels.

**The context is OpenGL ES 3.2, not desktop GL.** Shaders must be GLSL ES
(`#version 300 es`), and desktop-only entry points are not available.

## 3. JPEG decode: the C shim owns setjmp

`jpeglib.h` reports every failure through `jpeg_error_mgr.error_exit`, which
calls `exit()` unless a handler is installed - and the conventional handler is
`longjmp`, which Zig cannot do. That is the question ticket 001 was opened to
settle.

The shim route works. A small C file owns the `setjmp`/`longjmp` pair and
exposes plain functions; Zig sees only the shim's header, exactly as ADR 0003
does for exiv2:

```
$ ./zig-out/bin/jpegspike /usr/share/notcurses/PurpleDrank.jpg
status=0 width=600 height=640 components=3
broken-file status=1 (expect != 0)
```

A deliberately broken file comes back as an error value: no crash and no
`exit()`.

Three build facts worth carrying:

- `jpeglib.h` needs `<stdio.h>` included before it; on its own it fails with
  `unknown type name 'size_t'`.
- On Zig 0.17 a C source file is attached with
  `exe.root_module.addCSourceFile`, not `exe.addCSourceFile`.
- A `build.zig.zon` path dependency must be relative to the build root; an
  absolute path is rejected.

## 4. Which GL, and which shader API

The end-to-end run above reported OpenGL ES 3.2, because that is what
`GtkGLArea` allows by default. Two things correct that picture, both measured.

**ES 3.2 is not an old version.** It is the newest OpenGL ES; there is no ES 4.
Desktop GL goes further, to 4.6, and GTK exposes the choice as one call:

```zig
gtk.GLArea.setAllowedApis(area, .{ .gl = true, .gles = false });
```

The same probe then reports:

```
api: gl=true gles=false
GL_VERSION   = 4.6 (Core Profile) Mesa 26.2.6-arch1.1
GLSL_VERSION = 4.60
GL_RENDERER  = Mesa Intel(R) Graphics (LNL)
```

So the viewport gets **desktop GL 4.6 core and GLSL 4.60**, and it runs on the
real GPU rather than a software rasteriser. `GLAPI` is a packed struct of two
flags, so both APIs can be offered at once; iv asks for desktop GL.

**GTK's sanctioned shader path is `GtkGLArea`.** GSK does have a shader API -
`GskGLShader` and `GskGLShaderNode` - but it is deprecated:

```
$ grep -n 'DEPRECATED_IN_4_16' /usr/include/gtk-4.0/gsk/gskglshader.h
typedef struct _GskGLShader GskGLShader GDK_DEPRECATED_TYPE_IN_4_16_FOR(GtkGLArea);
```

`FOR(GtkGLArea)` is the deprecation's own instruction: use `GtkGLArea` instead.
There is no higher-level shader API to move to - the probe is already on the one
GTK points at, and GLSL is written by hand there.

## 5. What is still unverified

- PNG, WebP and the other backends: not spiked.
- Mipmaps and trilinear sampling (`glGenerateMipmap`): the probe samples with
  `GL_LINEAR` only.
- The desktop-GL path has only been asked for its version string; the textured
  quad was drawn on the ES context.
- Surviving a window resize in a real session: the probe renders once and quits.
- Colour management (lcms2) and the scaler: not on this path.

## What this settles

Every component the first image needs is reachable here, and the two that were
uncertain - GL entry points and libjpeg's error path - now have measured
answers. The MVP can be built against them.