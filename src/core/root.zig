//! The toolkit-free core: decode -> transform -> thumbnail -> cache. The only
//! C++ is the exiv2 shim (ADR 0003). The shell consumes this directory and
//! nothing deeper.
//!
//! Modules are re-exported below as they land; each carries its own tests, and
//! zig build test runs them without a display.

// TODO: what the core still needs, in the order it is worth building:
//   - decode: the registry of backends (decision 03) and the size contract
//     (ticket 002). JPEG is here; PNG and the rest are not.
//   - transform: the two-pass scaler (premultiply, area prefilter above 2x,
//     bicubic, unpremultiply) and the lcms2 colour step.
//   - thumbnail: the freedesktop on-disk cache contract.
//   - cache: a byte-budgeted cache of decoded frames, with the fixed thread pool
//     and step-boundary cancellation.
//   - exif: metadata through the exiv2 C shim.

pub const bitmap = @import("bitmap.zig");
pub const imageops = @import("imageops.zig");
pub const decode = @import("decode/root.zig");

pub const Bitmap = bitmap.Bitmap;
pub const Format = bitmap.Format;

test {
    // Load-bearing, for the reason spelled out in decode/root.zig: a module that
    // is imported but never analysed contributes none of its tests.
    _ = bitmap;
    _ = imageops;
    _ = decode;
}