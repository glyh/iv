//! The core's pixel type. This is an owning, tightly-packed buffer whose format
//! is explicit. The shell converts it to its own image type at its boundary and
//! nowhere else.
//!
//! The constructors validate what external input decides - a width taken from a
//! file header, a file's byte count - and return errors instead of letting the
//! arithmetic wrap or a later index run off the end. Nothing here panics on a
//! path external input can reach.

const std = @import("std");

pub const Error = error{
    /// The stride, or the total size, does not fit the arithmetic.
    TooLarge,
    /// The buffer is not exactly `stride * height` bytes.
    InvalidLength,
};

/// The formats the core produces. A grayscale JPEG stays single-channel all the
/// way to the screen.
///
/// A format is an identity, not a channel count: RGBA and CMYK are both four
/// channels, so the count cannot be the discriminant. Properties are asked for
/// by name instead.
pub const Format = enum {
    gray8,
    rgb888,
    rgba8888,

    /// Bytes one pixel occupies. Every format here is 8 bits per channel, so
    /// this happens to equal the channel count; it is written per format rather
    /// than read from the enum's discriminant.
    pub fn bytesPerPixel(self: Format) u32 {
        return switch (self) {
            .gray8 => 1,
            .rgb888 => 3,
            .rgba8888 => 4,
        };
    }
};

/// Bytes one row of `width` pixels occupies, refusing a width whose row does not
/// fit a u32.
fn strideFor(width: u32, format: Format) Error!u32 {
    return std.math.mul(u32, width, format.bytesPerPixel()) catch error.TooLarge;
}

pub const Bitmap = struct {
    data: []u8,
    width: u32,
    height: u32,
    stride: u32,
    format: Format,

    pub fn init(
        allocator: std.mem.Allocator,
        width: u32,
        height: u32,
        format: Format,
    ) (std.mem.Allocator.Error || Error)!Bitmap {
        const stride = try strideFor(width, format);
        const bytes = std.math.mul(usize, stride, height) catch return error.TooLarge;
        const data = try allocator.alloc(u8, bytes);
        @memset(data, 0);
        return .{
            .data = data,
            .width = width,
            .height = height,
            .stride = stride,
            .format = format,
        };
    }

    /// Takes ownership of `data`, which must be exactly `stride * height` bytes.
    /// This is where decoded file bytes arrive, so a mismatch is rejected rather
    /// than trusted: a short buffer used to index past its end on the first row
    /// read.
    pub fn fromBytes(
        data: []u8,
        width: u32,
        height: u32,
        format: Format,
    ) Error!Bitmap {
        const stride = try strideFor(width, format);
        const bytes = std.math.mul(usize, stride, height) catch return error.TooLarge;
        if (data.len != bytes) return error.InvalidLength;
        return .{
            .data = data,
            .width = width,
            .height = height,
            .stride = stride,
            .format = format,
        };
    }

    pub fn deinit(self: *Bitmap, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
        self.* = undefined;
    }

    /// `y` must be less than `height`. The constructors are what keep the
    /// dimensions honest, so an out-of-range row is a bug in the core, not
    /// something a file can ask for.
    pub fn row(self: *const Bitmap, y: u32) []const u8 {
        const start = @as(usize, y) * self.stride;
        return self.data[start..][0..self.stride];
    }

    /// The writable twin of `row`; only a non-const Bitmap can reach it.
    pub fn rowMut(self: *Bitmap, y: u32) []u8 {
        const start = @as(usize, y) * self.stride;
        return self.data[start..][0..self.stride];
    }

    /// Read-only: the slice is const, so a `*const Bitmap` cannot be written
    /// through its accessors.
    pub fn pixel(self: *const Bitmap, x: u32, y: u32) []const u8 {
        const c = self.format.bytesPerPixel();
        const start = @as(usize, y) * self.stride + @as(usize, x) * c;
        return self.data[start..][0..c];
    }

    pub fn pixelMut(self: *Bitmap, x: u32, y: u32) []u8 {
        const c = self.format.bytesPerPixel();
        const start = @as(usize, y) * self.stride + @as(usize, x) * c;
        return self.data[start..][0..c];
    }
};

const testing = std.testing;

test "init allocates zeroed, tightly packed data" {
    var bmp = try Bitmap.init(testing.allocator, 4, 3, .rgb888);
    defer bmp.deinit(testing.allocator);

    try testing.expectEqual(@as(u32, 12), bmp.stride);
    try testing.expectEqual(@as(usize, 36), bmp.data.len);
    for (bmp.data) |byte| try testing.expectEqual(@as(u8, 0), byte);
}

test "init refuses a width whose stride overflows" {
    // 1_431_655_765 * 4 does not fit a u32. It used to panic in Debug and wrap
    // in ReleaseFast, then allocate the wrapped size.
    try testing.expectError(error.TooLarge, Bitmap.init(testing.allocator, 1_431_655_765, 1, .rgba8888));
}

test "fromBytes refuses a buffer that is not stride * height" {
    var short = [3]u8{ 0, 0, 0 };
    try testing.expectError(error.InvalidLength, Bitmap.fromBytes(&short, 2, 2, .rgb888));
}

test "fromBytes takes a buffer of exactly stride * height" {
    const data = try testing.allocator.alloc(u8, 12);
    var bmp = try Bitmap.fromBytes(data, 2, 2, .rgb888);
    defer bmp.deinit(testing.allocator);

    @memcpy(bmp.pixelMut(1, 1), &[_]u8{ 9, 8, 7 });
    try testing.expectEqualSlices(u8, &[_]u8{ 9, 8, 7 }, bmp.pixel(1, 1));
}

test "row and pixel address the right bytes" {
    var bmp = try Bitmap.init(testing.allocator, 2, 2, .rgb888);
    defer bmp.deinit(testing.allocator);

    @memcpy(bmp.pixelMut(1, 1), &[_]u8{ 9, 8, 7 });
    try testing.expectEqualSlices(u8, &[_]u8{ 9, 8, 7 }, bmp.pixel(1, 1));
    try testing.expectEqualSlices(u8, &[_]u8{ 0, 0, 0 }, bmp.pixel(0, 1));
    try testing.expectEqualSlices(u8, &[_]u8{ 0, 0, 0, 9, 8, 7 }, bmp.row(1)[0..6]);
}
