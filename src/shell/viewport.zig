//! The Viewport: the shell's renderer. What crosses this seam is a `*const
//! Bitmap` and a target rectangle; the implementation uploads the pixels and
//! draws the quad, and the fit arithmetic stays on the shell side. See
//! `root.zig` for the rules and `docs/research/mvp-reachability.md` for the
//! measurements.
//!
//! TODO: the interface decision 12 asks for is a single concrete struct today,
//! because there is one implementation. A second one is what earns a vtable
//! (ticket 008).

const std = @import("std");
const gtk = @import("gtk");
const gl = @import("gl");
const core = @import("../core/root.zig");
const Bitmap = core.Bitmap;

// The shader sources live beside this file as GLSL, so they are highlighted
// and edited as GLSL rather than as escaped string literals.
const VERT = @embedFile("shaders/image.vert");
const FRAG = @embedFile("shaders/image.frag");

/// The unit quad: x, y, u, v. Texture row 0 is the image's top row, so v = 0 is
/// the top edge.
const quad = [_]f32{
    -1, -1, 0, 1,
    1,  -1, 1, 1,
    -1, 1,  0, 0,
    1,  1,  1, 0,
};

pub const Rect = struct { x: u32, y: u32, w: u32, h: u32 };

pub const GlViewport = struct {
    area: *gtk.GLArea,
    image: ?*const Bitmap = null,
    built: bool = false,
    uploaded: bool = false,
    program: c_uint = 0,
    vao: c_uint = 0,
    vbo: c_uint = 0,
    texture: c_uint = 0,
    scale_uniform: c_int = -1,
    /// Where the image landed in the last frame, in GL coordinates (origin at
    /// the bottom-left). Zero-sized until a frame is drawn.
    fitted: Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
    /// Why the last frame could not be drawn, if it could not.
    last_error: ?[]const u8 = null,

    pub fn init(self: *GlViewport, area: *gtk.GLArea) void {
        self.* = .{ .area = area };
        // GtkGLArea allows GLES by default; ask for desktop GL instead, which
        // is GL 4.6 core here. The shaders below are GLSL 460.
        gtk.GLArea.setAllowedApis(area, .{ .gl = true, .gles = false });
        gtk.GLArea.setAutoRender(area, 1);
    }

    /// Takes a borrowed pointer: the shell owns the bitmap and outlives the
    /// frame. Nothing crosses back into the core.
    pub fn setImage(self: *GlViewport, image: *const Bitmap) void {
        self.image = image;
        self.uploaded = false;
        gtk.GLArea.queueRender(self.area);
    }

    /// Draws one frame. The caller must be inside the `render` signal, where
    /// the GL context is current.
    pub fn renderFrame(self: *GlViewport) void {
        if (gtk.GLArea.getError(self.area)) |_| {
            self.last_error = "the GL area reported an error";
            return;
        }
        if (!self.built) self.build();

        const image = self.image orelse return;
        if (!self.uploaded) self.upload(image);

        const viewport = viewportOf(self.area);
        if (viewport.w == 0 or viewport.h == 0) return;

        // fitWithin never upscales, so a small image is shown at 1:1.
        const fitted = core.imageops.fitWithin(.{ .w = image.width, .h = image.height }, viewport);
        if (fitted.w == 0 or fitted.h == 0) return;

        self.fitted = .{
            .x = (viewport.w - fitted.w) / 2,
            .y = (viewport.h - fitted.h) / 2,
            .w = fitted.w,
            .h = fitted.h,
        };

        const sx = @as(f32, @floatFromInt(fitted.w)) / @as(f32, @floatFromInt(viewport.w));
        const sy = @as(f32, @floatFromInt(fitted.h)) / @as(f32, @floatFromInt(viewport.h));

        gl.glViewport(0, 0, @intCast(viewport.w), @intCast(viewport.h));
        gl.glClearColor(0.10, 0.10, 0.12, 1.0);
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);

        gl.glUseProgram(self.program);
        gl.glUniform2f(self.scale_uniform, sx, sy);
        gl.glActiveTexture(gl.GL_TEXTURE0);
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.texture);
        gl.glBindVertexArray(self.vao);
        gl.glDrawArrays(gl.GL_TRIANGLE_STRIP, 0, 4);
    }

    /// Reads one pixel from the current framebuffer. GL's origin is bottom-left,
    /// so `y` counts up from the bottom.
    pub fn readPixel(self: *GlViewport, x: u32, y: u32, out: *[4]u8) void {
        _ = self;
        gl.glReadPixels(@intCast(x), @intCast(y), 1, 1, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, out);
    }

    fn build(self: *GlViewport) void {
        gl.glGenVertexArrays(1, &self.vao);
        gl.glBindVertexArray(self.vao);
        gl.glGenBuffers(1, &self.vbo);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);
        gl.glBufferData(gl.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(quad)), &quad, gl.GL_STATIC_DRAW);

        const stride: c_int = 4 * @sizeOf(f32);
        gl.glVertexAttribPointer(0, 2, gl.GL_FLOAT, 0, stride, null);
        gl.glEnableVertexAttribArray(0);
        const uv_offset: ?*const anyopaque = @ptrFromInt(2 * @sizeOf(f32));
        gl.glVertexAttribPointer(1, 2, gl.GL_FLOAT, 0, stride, uv_offset);
        gl.glEnableVertexAttribArray(1);

        const vertex_shader = compile(gl.GL_VERTEX_SHADER, VERT);
        const fragment_shader = compile(gl.GL_FRAGMENT_SHADER, FRAG);
        self.program = gl.glCreateProgram();
        gl.glAttachShader(self.program, vertex_shader);
        gl.glAttachShader(self.program, fragment_shader);
        gl.glLinkProgram(self.program);
        gl.glDeleteShader(vertex_shader);
        gl.glDeleteShader(fragment_shader);

        // A program that did not link draws nothing, and the window would just
        // stay the clear colour with no explanation. Say so here, while the GL
        // error state the message comes from is still around.
        var linked: c_int = 0;
        gl.glGetProgramiv(self.program, gl.GL_LINK_STATUS, &linked);
        if (linked == 0) {
            var log: [1024]u8 = @splat(0);
            var length: c_int = 0;
            gl.glGetProgramInfoLog(self.program, @intCast(log.len), &length, &log);
            std.debug.print("iv: the viewport's shader program did not link: {s}\n", .{log[0..@intCast(length)]});
            self.last_error = "the shader program did not link";
        }

        self.scale_uniform = gl.glGetUniformLocation(self.program, "scale");

        gl.glGenTextures(1, &self.texture);
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.texture);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
        gl.glPixelStorei(gl.GL_UNPACK_ALIGNMENT, 1);
        self.built = true;
    }

    fn upload(self: *GlViewport, image: *const Bitmap) void {
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.texture);

        // A single-channel texture still has to sample as (r, r, r, 1), so the
        // swizzle does that instead of a shader branch. The other formats pass
        // their channels through unchanged.
        const swizzle: [4]c_int = if (image.format == .gray8)
            .{ gl.GL_RED, gl.GL_RED, gl.GL_RED, gl.GL_ONE }
        else
            .{ gl.GL_RED, gl.GL_GREEN, gl.GL_BLUE, gl.GL_ALPHA };
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_SWIZZLE_R, swizzle[0]);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_SWIZZLE_G, swizzle[1]);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_SWIZZLE_B, swizzle[2]);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_SWIZZLE_A, swizzle[3]);

        const internal_format: c_int = switch (image.format) {
            .gray8 => gl.GL_R8,
            .rgb888 => gl.GL_RGB8,
            .rgba8888 => gl.GL_RGBA8,
        };
        const source_format: c_uint = switch (image.format) {
            .gray8 => gl.GL_RED,
            .rgb888 => gl.GL_RGB,
            .rgba8888 => gl.GL_RGBA,
        };

        gl.glTexImage2D(
            gl.GL_TEXTURE_2D,
            0,
            internal_format,
            @intCast(image.width),
            @intCast(image.height),
            0,
            source_format,
            gl.GL_UNSIGNED_BYTE,
            image.data.ptr,
        );
        self.uploaded = true;
    }
};

/// The GL area's current size, as a `Size` with either side zero when the area
/// has not been laid out yet.
fn viewportOf(area: *gtk.GLArea) core.imageops.Size {
    const w = gtk.Widget.getWidth(area.as(gtk.Widget));
    const h = gtk.Widget.getHeight(area.as(gtk.Widget));
    return .{
        .w = if (w > 0) @intCast(w) else 0,
        .h = if (h > 0) @intCast(h) else 0,
    };
}

fn compile(kind: c_uint, source: [*:0]const u8) c_uint {
    const shader = gl.glCreateShader(kind);
    var text: [*c]const u8 = source;
    gl.glShaderSource(shader, 1, &text, null);
    gl.glCompileShader(shader);

    // The compile log is the useful one; a shader that fails here takes the
    // program's link down with it, and build() reports that.
    var compiled: c_int = 0;
    gl.glGetShaderiv(shader, gl.GL_COMPILE_STATUS, &compiled);
    if (compiled == 0) {
        var log: [1024]u8 = @splat(0);
        var length: c_int = 0;
        gl.glGetShaderInfoLog(shader, @intCast(log.len), &length, &log);
        std.debug.print("iv: a viewport shader did not compile: {s}\n", .{log[0..@intCast(length)]});
    }
    return shader;
}

