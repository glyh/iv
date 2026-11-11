//! Decoding: turning a file into pixels. One backend so far.
//!
//! TODO: decision 03 asks for a registry of backends, each declaring the
//! formats it claims and probing the first bytes. With a single backend a
//! direct call is honest; the registry is ticket 003.
//!
//! TODO: nothing applies EXIF orientation yet, so a photo whose orientation tag
//! is not 1 displays sideways. Ticket 010 settles it; ADR 0003 put the exiv2
//! shim in the core for exactly this.

const std = @import("std");
const bitmap = @import("../bitmap.zig");

pub const jpeg = @import("jpeg.zig");

pub const Error = jpeg.Error;

pub fn decode(
    allocator: std.mem.Allocator,
    path: [:0]const u8,
) (Error || std.mem.Allocator.Error)!bitmap.Bitmap {
    return jpeg.decode(allocator, path);
}

test {
    // Load-bearing, and silent if removed. Zig only collects the tests of files
    // it analyses, and in a test build nothing calls `decode`, so without this
    // reference `jpeg.zig`'s tests would stop running without any error at all.
    // Checked by breaking one of them: with this block the run reports 1
    // failure; without it the build succeeds.
    _ = jpeg;
}