//! The GTK application: one window, one GL area, one viewport.
//!
//! TODO: there is no menu, no file dialog and no keyboard handling yet; those
//! are ticket 006 and beyond.

const std = @import("std");
const gtk = @import("gtk");
const gio = @import("gio");
const gdk = @import("gdk");
const core = @import("../core/root.zig");
const viewport = @import("viewport.zig");

pub const Options = struct {
    /// Draw one frame, sample two pixels, report and quit, instead of waiting
    /// for a user. Needs a display; `zig build check` wraps it in xvfb-run.
    check: bool = false,
};

const State = struct {
    image: *const core.Bitmap,
    check: bool,
    app: ?*gtk.Application = null,
    view: viewport.GlViewport = undefined,
    left: [4]u8 = .{ 0, 0, 0, 0 },
    right: [4]u8 = .{ 0, 0, 0, 0 },
    sampled: bool = false,
};

var state: ?*State = null;

fn activate(app: *gtk.Application, _: ?*anyopaque) callconv(.c) void {
    const s = state orelse return;
    s.app = app;

    const window = gtk.ApplicationWindow.new(app);
    gtk.Window.setTitle(window.as(gtk.Window), "iv");
    gtk.Window.setDefaultSize(window.as(gtk.Window), 900, 700);

    const area = gtk.GLArea.new();
    s.view.init(area);
    _ = gtk.GLArea.signals.render.connect(area, ?*anyopaque, &onRender, null, .{});

    gtk.Window.setChild(window.as(gtk.Window), area.as(gtk.Widget));
    gtk.Widget.show(window.as(gtk.Widget));
    s.view.setImage(s.image);
}

fn onRender(_: *gtk.GLArea, _: *gdk.GLContext, _: ?*anyopaque) callconv(.c) c_int {
    const s = state orelse return 0;
    s.view.renderFrame();

    if (!s.check or s.sampled) return 1;

    // Sample inside the image, not across the window: fitWithin never upscales,
    // so a small image occupies a small centred rect.
    const rect = s.view.fitted;
    if (rect.w == 0 or rect.h == 0) return 1;
    s.sampled = true;
    s.view.readPixel(rect.x + rect.w / 4, rect.y + rect.h / 2, &s.left);
    s.view.readPixel(rect.x + 3 * rect.w / 4, rect.y + rect.h / 2, &s.right);

    if (s.app) |app| gio.Application.quit(app.as(gio.Application));
    return 1;
}

pub fn run(options: Options, image: *const core.Bitmap, argv: []const [*:0]const u8) u8 {
    var s = State{ .image = image, .check = options.check };
    state = &s;

    const app = gtk.Application.new("org.glyh.iv", .{});
    _ = gio.Application.signals.activate.connect(app, ?*anyopaque, &activate, null, .{});

    // Only argv[0]: the path is ours to handle, not GApplication's, and a
    // GtkApplication without HANDLES_OPEN errors on a file argument.
    const status = gio.Application.run(app.as(gio.Application), 1, @ptrCast(@constCast(argv.ptr)));

    if (!options.check) return @intCast(status);

    // test/fixtures/quadrants.jpg is red on the left half and blue on the right.
    const left_ok = s.left[0] > 120 and s.left[2] < 120;
    const right_ok = s.right[2] > 120 and s.right[0] < 120;
    const ok = s.sampled and left_ok and right_ok;
    std.debug.print("check: left={any} right={any} -> {s}\n", .{ s.left, s.right, if (ok) "PASS" else "FAIL" });
    return if (ok) 0 else 1;
}