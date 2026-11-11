//! The shell: the GTK4 application around the core. The core is a subdirectory
//! of this executable, not a separate package.
//!
//! # Reaching GTK (decision 12, ticket 004)
//!
//! The shell imports the `zig-gobject`-generated modules - `gtk`, `gdk`, `gio`,
//! `glib` - and calls those. It does not hand-write a binding layer, and it does
//! not `translate-c` the GTK headers itself: the binding is generated at build
//! time from the installed GObject-introspection data, and the only thing this
//! repository maintains is the pinned revision.
//!
//! That binding is the interop boundary. When a GTK call misbehaves, the search
//! space is the generated module plus the pinned revision - not this directory,
//! and not the shell at large. The measured recipe, including the two GIR files
//! this machine had to regenerate, is in `docs/research/zig-gobject.md`.
//!
//! Signals are typed and take a `user_data` pointer:
//! `gio.Application.signals.activate.connect(app, ?*anyopaque, &activate, null, .{})`.
//! There is no `g_signal_connect` call and no `GCallback` cast in the shell.
//!
//! # The Viewport seam (decision 12)
//!
//! The renderer sits behind a `Viewport` interface in the shell, so it can be
//! replaced without the core knowing. What crosses it: a `*const Bitmap` from
//! the core, and a target rectangle. The implementation uploads the pixels and
//! draws the quad; the fit arithmetic stays on the shell side, so
//! `imageops.fitWithin` has its caller there and a replacement renderer does
//! not re-derive it. Nothing crosses back into the core.
//!
//! # Events (ADR 0001)
//!
//! An app-internal event is a plain Zig callback with exactly one consumer.
//! GTK's own signals are consumed through the binding. A worker that must reach
//! the GTK main thread goes through `g_main_context_invoke`, which the binding
//! exposes like any other GLib call.
//!
//! # Lifecycle
//!
//! `main.zig` builds a `GtkApplication` and calls `g_application_run`; its
//! status is the process exit status, and that is where a failed GTK
//! initialization surfaces. Any path that calls `gtk_init_check` directly must
//! check it: GTK does not guard later calls, and `gtk_window_new()` after a
//! failed init segfaults (measured in `docs/research/gtk4-zig-interop.md`).
//!
//! # Build (decision 10)
//!
//! A pinned `zig-gobject` revision, its generator run as a build step over the
//! installed GIR files, and the resulting modules imported by name. That step
//! needs `gobject-introspection` on the build machine. The recipe is in
//! `docs/research/zig-gobject.md`.
//!
//! TODO: what the shell still needs, in the order it is worth building:
//!   - the application: `GtkApplication`, one window, and the `iv <path>`
//!     argument (ticket 006).
//!   - the viewport: the `Viewport` interface and its `GtkGLArea`
//!     implementation (ticket 008).
//!   - GL entry points: settled. `zig-gobject` has no `GL-1.0` module because
//!     the installed typelib is a stub with no functions in it, so the viewport
//!     reaches GL by `translate-c` over `epoxy/gl.h` and links `libepoxy`.
//!     `GtkGLArea` defaults to GLES, so the viewport asks for desktop GL with
//!     `setAllowedApis(.{ .gl = true, .gles = false })`: that is **GL 4.6 core
//!     and GLSL 4.60** on this machine, on the real GPU. Measured in
//!     `docs/research/mvp-reachability.md`.
//!   - display-free tests run under `xvfb-run`; GTK4 has no offscreen backend
//!     (decision 12).