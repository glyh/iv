//! The JPEG backend: libjpeg-turbo behind the C shim, which owns the setjmp
//! that libjpeg's error path needs.
//!
//! Pixels keep the file's own colour space. Nothing is converted on the read
//! path: a grayscale JPEG stays one channel all the way to the screen, which is
//! what `bitmap.zig` and decision 04 ask for.

const std = @import("std");
const bitmap = @import("../bitmap.zig");
const shim = @import("jpeg_shim");

// translate-c emits the enumerators as c_int constants and the struct field as
// c_uint, so the mapping works in the field's type.
const color_gray: u32 = @intCast(shim.IV_JPEG_GRAY);
const color_rgb: u32 = @intCast(shim.IV_JPEG_RGB);

pub const Error = error{
    /// The file is missing, unreadable, or not a JPEG libjpeg can parse.
    BadFile,
    /// The decoded dimensions overflow a usize, or the buffer did not fit.
    TooLarge,
    /// The file decodes to a colour space the core has no format for: CMYK,
    /// which libjpeg can produce (YCCK => CMYK) but cannot turn into RGB, and
    /// anything whose colour space libjpeg could not identify. Labelling
    /// either `rgb888` would be a guess about what the channels mean.
    UnsupportedColorSpace,
};

/// The format a colour space means. Decision 04 makes a format an identity, so
/// the key is the identity and not the channel count.
///
/// The `else` arm is what makes this safe to extend: a colour space added on
/// the C side without a case here is refused, not mislabelled.
fn formatFor(color_space: u32) Error!bitmap.Format {
    return switch (color_space) {
        color_gray => .gray8,
        color_rgb => .rgb888,
        else => error.UnsupportedColorSpace,
    };
}

/// Decodes `path` into the format its colour space calls for. The caller owns
/// the returned bitmap.
pub fn decode(
    allocator: std.mem.Allocator,
    path: [:0]const u8,
) (Error || std.mem.Allocator.Error)!bitmap.Bitmap {
    var info: shim.struct_iv_jpeg_info = undefined;
    if (shim.iv_jpeg_probe(path.ptr, &info) != shim.IV_JPEG_OK) return error.BadFile;
    if (info.width == 0 or info.height == 0) return error.BadFile;

    const format = try formatFor(info.color_space);

    const pixels = std.math.mul(usize, info.width, info.height) catch return error.TooLarge;
    const bytes = std.math.mul(usize, pixels, format.bytesPerPixel()) catch return error.TooLarge;

    const data = try allocator.alloc(u8, bytes);
    errdefer allocator.free(data);

    // The shim writes scanlines straight into `data`, so this is one pass with
    // no repacking.
    const status = shim.iv_jpeg_decode(path.ptr, data.ptr, data.len, &info);
    if (status != shim.IV_JPEG_OK) {
        return if (status == shim.IV_JPEG_TOO_SMALL) error.TooLarge else error.BadFile;
    }
    return bitmap.Bitmap.fromBytes(data, info.width, info.height, format) catch return error.TooLarge;
}

const testing = std.testing;

/// The mean of a patch, one entry per channel, so a lossy codec is asked a
/// question about a region rather than about one pixel that might sit on an
/// edge artefact.
fn patchMean(bmp: *const bitmap.Bitmap, x0: u32, x1: u32, y0: u32, y1: u32) [4]u32 {
    var sum = [_]u32{ 0, 0, 0, 0 };
    var n: u32 = 0;
    var y = y0;
    while (y < y1) : (y += 1) {
        var x = x0;
        while (x < x1) : (x += 1) {
            const px = bmp.pixel(x, y);
            for (px, 0..) |value, i| sum[i] += value;
            n += 1;
        }
    }
    var mean: [4]u32 = undefined;
    for (0..4) |i| mean[i] = sum[i] / n;
    return mean;
}

/// Squared Euclidean distance over `channels` channels. JPEG is lossy, so a
/// decode is checked as "close enough" and not as equality; one number to put a
/// bound on beats a threshold per channel.
fn distanceSquared(actual: [4]u32, expected: [4]u32, channels: u32) u32 {
    var total: u32 = 0;
    for (0..channels) |i| {
        const d = if (actual[i] > expected[i]) actual[i] - expected[i] else expected[i] - actual[i];
        total += d * d;
    }
    return total;
}

/// A bounded distance, with room for the fixture being regenerated at another
/// quality: the committed one is exact, so this is all headroom.
const colour_tolerance: u32 = 24;

test "a colour JPEG decodes to rgb888" {
    // test/fixtures/quadrants.jpg: 32x24, left half red, right half blue.
    // Generated for this repository with Pillow; GPL-3.0 like the rest of it.
    var bmp = try decode(testing.allocator, "test/fixtures/quadrants.jpg");
    defer bmp.deinit(testing.allocator);

    try testing.expectEqual(@as(u32, 32), bmp.width);
    try testing.expectEqual(@as(u32, 24), bmp.height);
    try testing.expectEqual(bitmap.Format.rgb888, bmp.format);

    const bound = 3 * colour_tolerance * colour_tolerance;
    const red = patchMean(&bmp, 2, 8, 9, 15);
    const blue = patchMean(&bmp, 24, 30, 9, 15);
    try testing.expect(distanceSquared(red, .{ 255, 0, 0, 0 }, 3) <= bound);
    try testing.expect(distanceSquared(blue, .{ 0, 0, 255, 0 }, 3) <= bound);
}

test "a grayscale JPEG stays single channel" {
    // test/fixtures/gray.jpg: 24x16, left dark, right light.
    var bmp = try decode(testing.allocator, "test/fixtures/gray.jpg");
    defer bmp.deinit(testing.allocator);

    try testing.expectEqual(@as(u32, 24), bmp.width);
    try testing.expectEqual(@as(u32, 16), bmp.height);
    try testing.expectEqual(bitmap.Format.gray8, bmp.format);

    const bound = colour_tolerance * colour_tolerance;
    const dark = patchMean(&bmp, 2, 10, 5, 11);
    const light = patchMean(&bmp, 14, 22, 5, 11);
    try testing.expect(distanceSquared(dark, .{ 30, 0, 0, 0 }, 1) <= bound);
    try testing.expect(distanceSquared(light, .{ 220, 0, 0, 0 }, 1) <= bound);
}

test "CMYK is refused with its own error, not BadFile" {
    // Four components is CMYK: libjpeg's supported conversions are
    // YCbCr => RGB, YCbCr => GRAYSCALE, RGB => GRAYSCALE, GRAYSCALE => RGB and
    // YCCK => CMYK, so there is no CMYK => RGB and no format to hold it.
    try testing.expectError(error.UnsupportedColorSpace, decode(testing.allocator, "test/fixtures/cmyk.jpg"));
}

test "a file that is not a JPEG is an error value, not a crash" {
    try testing.expectError(error.BadFile, decode(testing.allocator, "test/fixtures/broken.jpg"));
}

test "a missing file is an error value" {
    try testing.expectError(error.BadFile, decode(testing.allocator, "test/fixtures/does-not-exist.jpg"));
}

