const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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

    // Tests live beside the code. The core's root module imports every core
    // module, so it is the test root; main.zig has no tests and is not one.
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/core/root.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    const test_step = b.step("test", "Run the tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
}
