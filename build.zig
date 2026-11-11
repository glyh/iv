const std = @import("std");

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

    // translate-c reads `jpeg_shim.h`, never `jpeglib.h`: the shim exists so
    // that libjpeg's structs, and the setjmp its error path needs, stay in C.
    // The header and docs/research/mvp-reachability.md carry the reasoning.
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
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    const run_step = b.step("run", "Run iv");
    run_step.dependOn(&run_cmd.step);

    // Tests live beside the code and stay display-free: the core's root module
    // imports every core module, so it is the test root.
    const core_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/core/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "jpeg_shim", .module = jpeg_shim }},
    }) });
    const test_step = b.step("test", "Run the tests");
    test_step.dependOn(&b.addRunArtifact(core_tests).step);
}