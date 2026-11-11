//! The application entry point: `iv [--check] <file>`.

const std = @import("std");
const core = @import("core/root.zig");
const shell = @import("shell/root.zig");

pub fn main(init: std.process.Init) void {
    const argv = init.minimal.args.vector;

    var check = false;
    var path: ?[:0]const u8 = null;
    for (argv[1..]) |arg| {
        const text = std.mem.span(arg);
        if (std.mem.eql(u8, text, "--check")) {
            check = true;
        } else if (path == null) {
            path = text;
        } else {
            std.debug.print("iv: unexpected argument: {s}\n", .{text});
            std.process.exit(2);
        }
    }

    const file = path orelse {
        std.debug.print("usage: iv [--check] <file>\n", .{});
        std.process.exit(2);
    };

    const allocator = std.heap.page_allocator;
    var image = core.decode.decode(allocator, file) catch |err| {
        // A bad file is a message, not a crash and not an exit() from inside a
        // decoder (decision 03).
        std.debug.print("iv: cannot read {s}: {s}\n", .{ file, @errorName(err) });
        std.process.exit(1);
    };

    const status = shell.run(.{ .check = check }, &image, argv);
    image.deinit(allocator);
    std.process.exit(status);
}