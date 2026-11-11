#ifndef IV_JPEG_SHIM_H
#define IV_JPEG_SHIM_H

#include <stddef.h>
#include <stdint.h>

// libjpeg reports every failure through jpeg_error_mgr.error_exit, which calls
// exit() unless a handler is installed, and the conventional handler is
// longjmp. Zig has no setjmp, so this shim owns the jump and never lets it
// cross into Zig (ADR 0003).
//
// This header is what `build.zig` runs translate-c over - never `jpeglib.h`.
// Keep `#include <jpeglib.h>` out of it. The moment Zig can see `struct
// jpeg_decompress_struct` and `jpeg_error_mgr`, the obvious next move is to
// install the error handler in Zig, and that cannot be made sound: the language
// has no "returns twice", so the optimiser is free to keep locals in registers
// across the call and hand back a stale value. ziglang/zig#1656 is the upstream
// ruling, #21810 a reproduction, and docs/research/mvp-reachability.md records
// the measurement on this machine.

enum iv_jpeg_status {
    IV_JPEG_OK = 0,
    IV_JPEG_BAD_FILE = 1,
    IV_JPEG_TOO_SMALL = 2,
};

// The colour space a decode will produce, in this shim's own terms rather than
// libjpeg's. This is an identity, not a channel count: three components can be
// RGB or a JCS_UNKNOWN file libjpeg passed through untouched, and the caller
// needs a pixel format for one of those, not for "three".
//
// OTHER covers everything the core has no format for - CMYK above all, whose
// YCCK => CMYK conversion libjpeg supports but CMYK => RGB it does not.
enum iv_jpeg_color_space {
    IV_JPEG_GRAY = 0,
    IV_JPEG_RGB = 1,
    IV_JPEG_OTHER = 2,
};

struct iv_jpeg_info {
    uint32_t width;
    uint32_t height;
    // One of enum iv_jpeg_color_space.
    uint32_t color_space;
};

// Reads the header and stops. Nothing the caller needs is settled later:
// jpeg_read_header already sets out_color_space from the file's own colour
// space, and the shim never asks for a conversion. Calling
// jpeg_start_decompress here would build the decompression structures and the
// conversion tables for nothing, and that is most of a decode's cost.
enum iv_jpeg_status iv_jpeg_probe(const char *path, struct iv_jpeg_info *out);

// Decodes to tightly packed pixels in the file's own colour space: exactly
// `width * height * components` bytes, which must fit `capacity`. No colour
// space is requested, so no channel is added, dropped or converted. Refuses if
// the components that arrive do not match the colour space the probe reported,
// rather than writing at a stride the caller did not allocate for.
enum iv_jpeg_status iv_jpeg_decode(const char *path, uint8_t *out, size_t capacity, struct iv_jpeg_info *info);

#endif