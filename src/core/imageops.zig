//! The core's pixel math: scale, crop, flip, rotate. Everything here owns its
//! output and takes an allocator; nothing knows about Qt.
//!
//! TODO: the scaler is a first cut. `nearest` and `bilinear` are the only
//! filters, and `bilinear` reads straight alpha, so a transparent edge blends
//! against un-premultiplied colour. The real pipeline is two-pass: premultiply,
//! area prefilter above 2x, then bicubic, then unpremultiply (decisions 04 and
//! 06).

const std = @import("std");
const bitmap = @import("bitmap.zig");
const Bitmap = bitmap.Bitmap;

pub const Size = struct { w: u32, h: u32 };

pub const Filter = enum {
    nearest,
    bilinear,
};

/// Largest size that fits `max_w x max_h` while keeping the aspect ratio. Zero on
/// either side means there is no room, and the answer is 0x0 - it used to return
/// a 0x1 or 1x0 bitmap, which is not a size anything can use.
pub fn fitWithin(width: u32, height: u32, max_w: u32, max_h: u32) Size {
    if (width == 0 or height == 0 or max_w == 0 or max_h == 0) return .{ .w = 0, .h = 0 };
    if (width <= max_w and height <= max_h) return .{ .w = width, .h = height };

    // u64: the product of two u32s does not fit a u32, and a cast back that
    // overflows would panic.
    const scaled_h = @as(u64, height) * max_w / width;
    if (scaled_h > 0 and scaled_h <= max_h) return .{ .w = max_w, .h = @intCast(scaled_h) };

    const scaled_w = @as(u64, width) * max_h / height;
    return .{
        .w = @max(1, @as(u32, @intCast(@min(scaled_w, @as(u64, max_w))))),
        .h = max_h,
    };
}

pub fn scale(
    allocator: std.mem.Allocator,
    src: *const Bitmap,
    dst_w: u32,
    dst_h: u32,
    filter: Filter,
) !Bitmap {
    if (dst_w == 0 or dst_h == 0) return error.EmptyOutput;
    if (src.width == 0 or src.height == 0) return error.EmptyInput;
    return switch (filter) {
        .nearest => scaleNearest(allocator, src, dst_w, dst_h),
        .bilinear => scaleBilinear(allocator, src, dst_w, dst_h),
    };
}

fn scaleNearest(
    allocator: std.mem.Allocator,
    src: *const Bitmap,
    dst_w: u32,
    dst_h: u32,
) !Bitmap {
    var dst = try Bitmap.init(allocator, dst_w, dst_h, src.format);
    errdefer dst.deinit(allocator);

    var y: u32 = 0;
    while (y < dst_h) : (y += 1) {
        const sy = @min(src.height - 1, @as(u32, @intCast(
            @as(u64, y) * src.height / dst_h,
        )));
        var x: u32 = 0;
        while (x < dst_w) : (x += 1) {
            const sx = @min(src.width - 1, @as(u32, @intCast(
                @as(u64, x) * src.width / dst_w,
            )));
            @memcpy(dst.pixelMut(x, y), src.pixel(sx, sy));
        }
    }
    return dst;
}

fn scaleBilinear(
    allocator: std.mem.Allocator,
    src: *const Bitmap,
    dst_w: u32,
    dst_h: u32,
) !Bitmap {
    var dst = try Bitmap.init(allocator, dst_w, dst_h, src.format);
    errdefer dst.deinit(allocator);

    const c = src.format.bytesPerPixel();
    const x_ratio = if (dst_w > 1)
        @as(f32, @floatFromInt(src.width - 1)) / @as(f32, @floatFromInt(dst_w - 1))
    else
        0;
    const y_ratio = if (dst_h > 1)
        @as(f32, @floatFromInt(src.height - 1)) / @as(f32, @floatFromInt(dst_h - 1))
    else
        0;

    var y: u32 = 0;
    while (y < dst_h) : (y += 1) {
        const fy = @as(f32, @floatFromInt(y)) * y_ratio;
        const y0: u32 = @intFromFloat(@floor(fy));
        const y1 = @min(y0 + 1, src.height - 1);
        const wy = fy - @floor(fy);

        var x: u32 = 0;
        while (x < dst_w) : (x += 1) {
            const fx = @as(f32, @floatFromInt(x)) * x_ratio;
            const x0: u32 = @intFromFloat(@floor(fx));
            const x1 = @min(x0 + 1, src.width - 1);
            const wx = fx - @floor(fx);

            const p00 = src.pixel(x0, y0);
            const p01 = src.pixel(x1, y0);
            const p10 = src.pixel(x0, y1);
            const p11 = src.pixel(x1, y1);
            const out = dst.pixelMut(x, y);

            for (0..c) |i| {
                const top = @as(f32, @floatFromInt(p00[i])) * (1 - wx) +
                    @as(f32, @floatFromInt(p01[i])) * wx;
                const bottom = @as(f32, @floatFromInt(p10[i])) * (1 - wx) +
                    @as(f32, @floatFromInt(p11[i])) * wx;
                const value = std.math.clamp(top * (1 - wy) + bottom * wy, 0, 255);
                out[i] = @intFromFloat(@round(value));
            }
        }
    }
    return dst;
}

pub fn crop(
    allocator: std.mem.Allocator,
    src: *const Bitmap,
    x: u32,
    y: u32,
    width: u32,
    height: u32,
) !Bitmap {
    if (x >= src.width or y >= src.height) return error.OutOfBounds;
    const w = @min(width, src.width - x);
    const h = @min(height, src.height - y);
    if (w == 0 or h == 0) return error.EmptyOutput;

    var dst = try Bitmap.init(allocator, w, h, src.format);
    errdefer dst.deinit(allocator);

    const c = src.format.bytesPerPixel();
    var row: u32 = 0;
    while (row < h) : (row += 1) {
        // usize indexing: x * c and w * c overflow a u32 on a large image.
        const from = @as(usize, x) * c;
        @memcpy(dst.rowMut(row), src.row(y + row)[from..][0 .. @as(usize, w) * c]);
    }
    return dst;
}

pub fn flipH(allocator: std.mem.Allocator, src: *const Bitmap) !Bitmap {
    var dst = try Bitmap.init(allocator, src.width, src.height, src.format);
    errdefer dst.deinit(allocator);

    const c = src.format.bytesPerPixel();
    var y: u32 = 0;
    while (y < src.height) : (y += 1) {
        const source_row = src.row(y);
        const dest_row = dst.rowMut(y);
        var x: u32 = 0;
        while (x < src.width) : (x += 1) {
            const sx = src.width - 1 - x;
            @memcpy(
                dest_row[@as(usize, x) * c ..][0..c],
                source_row[@as(usize, sx) * c ..][0..c],
            );
        }
    }
    return dst;
}

pub fn flipV(allocator: std.mem.Allocator, src: *const Bitmap) !Bitmap {
    var dst = try Bitmap.init(allocator, src.width, src.height, src.format);
    errdefer dst.deinit(allocator);

    var y: u32 = 0;
    while (y < src.height) : (y += 1) {
        @memcpy(dst.rowMut(y), src.row(src.height - 1 - y));
    }
    return dst;
}

/// Quarter turns clockwise, 0..3.
pub fn rotate90(allocator: std.mem.Allocator, src: *const Bitmap, quarter_turns: u32) !Bitmap {
    const turns = quarter_turns % 4;
    if (turns == 0) {
        var copy = try Bitmap.init(allocator, src.width, src.height, src.format);
        errdefer copy.deinit(allocator);
        @memcpy(copy.data, src.data);
        return copy;
    }

    const dst_w = if (turns == 2) src.width else src.height;
    const dst_h = if (turns == 2) src.height else src.width;
    var dst = try Bitmap.init(allocator, dst_w, dst_h, src.format);
    errdefer dst.deinit(allocator);

    var y: u32 = 0;
    while (y < dst_h) : (y += 1) {
        var x: u32 = 0;
        while (x < dst_w) : (x += 1) {
            const s = switch (turns) {
                1 => .{ y, src.height - 1 - x },
                2 => .{ src.width - 1 - x, src.height - 1 - y },
                3 => .{ src.width - 1 - y, x },
                else => unreachable,
            };
            @memcpy(dst.pixelMut(x, y), src.pixel(s[0], s[1]));
        }
    }
    return dst;
}

const testing = std.testing;

fn gray2x2(v: [4]u8) Bitmap {
    var bmp = Bitmap.init(testing.allocator, 2, 2, .gray8) catch unreachable;
    for (v, 0..) |value, i| bmp.data[i] = value;
    return bmp;
}

test "fitWithin keeps the aspect ratio and never upscales" {
    try testing.expectEqualDeep(Size{ .w = 100, .h = 50 }, fitWithin(100, 50, 200, 200));
    try testing.expectEqual(@as(u32, 100), fitWithin(4000, 2000, 100, 100).w);
    try testing.expectEqual(@as(u32, 50), fitWithin(4000, 2000, 100, 100).h);
    try testing.expectEqual(@as(u32, 100), fitWithin(100, 400, 100, 100).h);
}

test "fitWithin with no room on either side is empty" {
    try testing.expectEqualDeep(Size{ .w = 0, .h = 0 }, fitWithin(100, 50, 0, 100));
    try testing.expectEqualDeep(Size{ .w = 0, .h = 0 }, fitWithin(100, 50, 100, 0));
    try testing.expectEqualDeep(Size{ .w = 0, .h = 0 }, fitWithin(0, 50, 100, 100));
    try testing.expectEqualDeep(Size{ .w = 0, .h = 0 }, fitWithin(100, 0, 100, 100));
}

test "nearest scale up is replication" {
    var src = gray2x2(.{ 0, 1, 2, 3 });
    defer src.deinit(testing.allocator);
    var dst = try scale(testing.allocator, &src, 4, 4, .nearest);
    defer dst.deinit(testing.allocator);

    try testing.expectEqual(@as(u8, 0), dst.pixel(0, 0)[0]);
    try testing.expectEqual(@as(u8, 1), dst.pixel(3, 0)[0]);
    try testing.expectEqual(@as(u8, 2), dst.pixel(0, 3)[0]);
    try testing.expectEqual(@as(u8, 3), dst.pixel(3, 3)[0]);
}

test "bilinear scale of a constant image stays constant" {
    var src = gray2x2(.{ 7, 7, 7, 7 });
    defer src.deinit(testing.allocator);
    var dst = try scale(testing.allocator, &src, 5, 3, .bilinear);
    defer dst.deinit(testing.allocator);
    for (dst.data) |byte| try testing.expectEqual(@as(u8, 7), byte);
}

test "crop takes the requested region and clamps it" {
    var src = gray2x2(.{ 0, 1, 2, 3 });
    defer src.deinit(testing.allocator);
    var dst = try crop(testing.allocator, &src, 1, 0, 5, 1);
    defer dst.deinit(testing.allocator);
    try testing.expectEqual(@as(u32, 1), dst.width);
    try testing.expectEqual(@as(u8, 1), dst.pixel(0, 0)[0]);
}

test "flipH and flipV" {
    var src = gray2x2(.{ 0, 1, 2, 3 });
    defer src.deinit(testing.allocator);
    var h = try flipH(testing.allocator, &src);
    defer h.deinit(testing.allocator);
    var v = try flipV(testing.allocator, &src);
    defer v.deinit(testing.allocator);
    try testing.expectEqualSlices(u8, &[_]u8{ 1, 0, 3, 2 }, h.data);
    try testing.expectEqualSlices(u8, &[_]u8{ 2, 3, 0, 1 }, v.data);
}

test "rotate90 clockwise and its inverse" {
    var src = gray2x2(.{ 0, 1, 2, 3 });
    defer src.deinit(testing.allocator);
    var cw = try rotate90(testing.allocator, &src, 1);
    defer cw.deinit(testing.allocator);
    try testing.expectEqualSlices(u8, &[_]u8{ 2, 0, 3, 1 }, cw.data);
    var back = try rotate90(testing.allocator, &cw, 3);
    defer back.deinit(testing.allocator);
    try testing.expectEqualSlices(u8, &[_]u8{ 0, 1, 2, 3 }, back.data);
}
