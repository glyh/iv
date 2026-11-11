const std = @import("std");
const bindings = @import("build/bindings.zig");

/// What `cModule` needs to build one C-backed module.
const CModule = struct {
    /// The wrapper header `translate-c` reads. It must not include the C
    /// library's own headers - the header itself says why.
    header: []const u8,
    /// The C implementation, when the module has one.
    source: ?[]const u8 = null,
    /// The system library the module needs, resolved through pkg-config.
    library: []const u8,
};

/// A module built from a C header: the header is translated, the C source (if
/// there is one) is compiled into the module, and the system library is
/// attached to the module rather than to each consumer, so importing the module
/// is enough to link it.
///
/// The library has to be added before `createModule`: `TranslateC` builds a
/// fresh module on each call and copies the libraries accumulated so far.
fn cModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    options: CModule,
) *std.Build.Module {
    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path(options.header),
        .target = target,
        .optimize = optimize,
    });
    translate_c.linkSystemLibrary(options.library, .{});
    const module = translate_c.createModule();
    if (options.source) |source| {
        module.addCSourceFile(.{ .file = b.path(source), .flags = &.{} });
        module.link_libc = true;
    }
    return module;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // The GTK bindings, generated into the build cache by the pinned
    // generator. See build/bindings.zig.
    const gtk = bindings.add(b, target, optimize);

    // GL comes from libepoxy, because zig-gobject binds no GL; the JPEG shim
    // exists to keep libjpeg's setjmp in C. docs/research/mvp-reachability.md
    // records the measurements behind both.
    const gl = cModule(b, target, optimize, .{
        .header = "src/shell/gl.h",
        .library = "epoxy",
    });
    const jpeg_shim = cModule(b, target, optimize, .{
        .header = "src/core/decode/jpeg_shim.h",
        .source = "src/core/decode/jpeg_shim.c",
        .library = "jpeg",
    });

    // One executable. The core is a subdirectory of it, not a separate package,
    // so there is no library module to export.
    const exe = b.addExecutable(.{
        .name = "iv",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "gtk", .module = gtk.module("gtk4") },
                .{ .name = "gdk", .module = gtk.module("gdk4") },
                .{ .name = "gio", .module = gtk.module("gio2") },
                .{ .name = "gl", .module = gl },
                .{ .name = "jpeg_shim", .module = jpeg_shim },
            },
        }),
    });
    b.installArtifact(exe);

    // The image to open. With no option the step shows the committed fixture,
    // so `zig build run` does something instead of printing usage and failing;
    // `zig build run -Dfile=<path>` opens something else.
    //
    // A build option rather than the arguments after `--`: Zig hands a build
    // script only `-D` options, and `--` args are expanded by the runner for an
    // `addPassthruArgs` marker it never shows the script.
    const image = b.option([]const u8, "file", "the image to open") orelse "test/fixtures/quadrants.jpg";
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    // The step exists to run a program, so it has side effects.
    run_cmd.has_side_effects = true;
    run_cmd.addArg(image);
    const run_step = b.step("run", "Run iv on an image");
    run_step.dependOn(&run_cmd.step);

    // Tests live beside the code and stay display-free: the core's root module
    // imports every core module, so it is the test root. The shell is not in it,
    // because anything that builds a window needs a display (decision 11).
    const core_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/core/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "jpeg_shim", .module = jpeg_shim }},
    }) });
    const test_step = b.step("test", "Run the tests");
    test_step.dependOn(&b.addRunArtifact(core_tests).step);

    // The display check of decision 11: render a fixture under Xvfb, read two
    // pixels back, and report.
    const check_cmd = b.addSystemCommand(&.{"xvfb-run"});
    // Likewise, and a check that quietly stops checking is the failure this
    // flag exists to prevent.
    check_cmd.has_side_effects = true;
    check_cmd.addArg("-a");
    check_cmd.addArtifactArg(exe);
    check_cmd.addArgs(&.{ "--check", "test/fixtures/quadrants.jpg" });
    const check_step = b.step("check", "Render a fixture under Xvfb and verify the pixels");
    check_step.dependOn(&check_cmd.step);
}