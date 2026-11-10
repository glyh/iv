//! The application entry point. The core is a subdirectory of this executable,
//! not a separate package.

const std = @import("std");
const core = @import("core/root.zig");

pub fn main(init: std.process.Init) !void {
    _ = init;
    _ = core;
    std.debug.print("iv: the core is not implemented yet\n", .{});
}
