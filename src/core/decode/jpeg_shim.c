#include "jpeg_shim.h"

#include <setjmp.h>
#include <stddef.h>
#include <stdio.h>

#include <jpeglib.h>

// The only frame in this codebase that may hold a setjmp landing pad. The jump
// never crosses into Zig: longjmp comes back here, this function cleans up by
// hand (nothing else runs - no defer, no destructor, no free), and returns an
// enum.
//
// This cannot move into Zig, and `callconv(.c)` is not the missing piece. Zig's
// spec has no "returns twice", so LLVM may keep a local in a register across
// the call and hand back a stale value after the jump, and a Zig `defer` in the
// skipped frames never runs. Measured in docs/research/mvp-reachability.md;
// upstream in ziglang/zig#1656 and #21810.
struct iv_jpeg_error {
    struct jpeg_error_mgr pub;
    jmp_buf jump;
};

// The cast in iv_error_exit is only correct because `pub` sits at offset 0: that
// is what makes a `struct jpeg_error_mgr *` recoverable as a
// `struct iv_jpeg_error *`. Put anything ahead of `pub` and the cast silently
// reads the wrong bytes and longjmps through a garbage jmp_buf - so the
// assumption is checked at build time instead of trusted. libjpeg's own
// example.c depends on the same layout without asserting it; the attribute here
// is that this one fails to compile rather than fails at run time.
_Static_assert(offsetof(struct iv_jpeg_error, pub) == 0,
               "iv_jpeg_error.pub must stay the first member: iv_error_exit casts cinfo->err back to the wrapper");

static void iv_error_exit(j_common_ptr cinfo) {
    struct iv_jpeg_error *err = (struct iv_jpeg_error *)cinfo->err;
    longjmp(err->jump, 1);
}

// The handler is stored in jpeg_error_mgr.error_exit, and C only warns about an
// incompatible function-pointer assignment - it would compile and then be
// called through the wrong type. So the signature is checked at build time. The
// expected type is read off the field itself, so this fires if either side
// drifts. Note that __typeof__ does not decay a function name: &iv_error_exit
// is the pointer type the field holds, iv_error_exit alone is the function
// type, and comparing that against a pointer would always be false.
_Static_assert(
    __builtin_types_compatible_p(__typeof__(&iv_error_exit),
                                 __typeof__(((struct jpeg_error_mgr *)0)->error_exit)),
    "iv_error_exit must match the type jpeg_error_mgr.error_exit expects");

// The colour space a decode produces, in this shim's terms. jpeg_read_header
// sets out_color_space from the file's own colour space, and nothing here ever
// requests a conversion, so this is also what iv_jpeg_decode emits. Anything
// else - CMYK, or a colour space libjpeg could not identify - is OTHER, and the
// caller refuses it rather than guessing a pixel format.
static uint32_t iv_color_space(const struct jpeg_decompress_struct *cinfo) {
    switch (cinfo->out_color_space) {
        case JCS_GRAYSCALE: return IV_JPEG_GRAY;
        case JCS_RGB:       return IV_JPEG_RGB;
        default:            return IV_JPEG_OTHER;
    }
}

// Components per pixel that this shim will write for a colour space; 0 means it
// has no format for it and must not write at all.
static uint32_t iv_components_for(uint32_t color_space) {
    switch (color_space) {
        case IV_JPEG_GRAY: return 1;
        case IV_JPEG_RGB:  return 3;
        default:           return 0;
    }
}

// Every entry point repeats this setup, and every one of them has to run it in
// the same order: install the handler first, then set the landing pad. An error
// raised before setjmp is installed would reach the default error_exit and call
// exit().
enum iv_jpeg_status iv_jpeg_probe(const char *path, struct iv_jpeg_info *out) {
    struct jpeg_decompress_struct cinfo;
    struct iv_jpeg_error jerr;
    FILE *f = fopen(path, "rb");
    if (!f) return IV_JPEG_BAD_FILE;

    cinfo.err = jpeg_std_error(&jerr.pub);
    jerr.pub.error_exit = iv_error_exit;
    if (setjmp(jerr.jump)) {
        jpeg_destroy_decompress(&cinfo);
        fclose(f);
        return IV_JPEG_BAD_FILE;
    }

    jpeg_create_decompress(&cinfo);
    jpeg_stdio_src(&cinfo, f);
    jpeg_read_header(&cinfo, 1);
    // Deliberately no jpeg_start_decompress: it would build the decompression
    // structures and colour conversion tables, and iv_jpeg_decode builds them
    // again. Measured at roughly a decode's worth of time for nothing.
    out->width = cinfo.image_width;
    out->height = cinfo.image_height;
    out->color_space = iv_color_space(&cinfo);
    jpeg_destroy_decompress(&cinfo);
    fclose(f);
    return IV_JPEG_OK;
}

enum iv_jpeg_status iv_jpeg_decode(const char *path, uint8_t *out, size_t capacity, struct iv_jpeg_info *info) {
    struct jpeg_decompress_struct cinfo;
    struct iv_jpeg_error jerr;
    FILE *f = fopen(path, "rb");
    if (!f) return IV_JPEG_BAD_FILE;

    cinfo.err = jpeg_std_error(&jerr.pub);
    jerr.pub.error_exit = iv_error_exit;
    if (setjmp(jerr.jump)) {
        jpeg_destroy_decompress(&cinfo);
        fclose(f);
        return IV_JPEG_BAD_FILE;
    }

    jpeg_create_decompress(&cinfo);
    jpeg_stdio_src(&cinfo, f);
    jpeg_read_header(&cinfo, 1);
    jpeg_start_decompress(&cinfo);

    // The caller sized its buffer from the colour space iv_jpeg_probe reported.
    // If what decompression actually produces disagrees with it, writing would
    // run at a stride the caller never allocated for - so refuse instead.
    uint32_t color_space = iv_color_space(&cinfo);
    uint32_t expected = iv_components_for(color_space);
    uint32_t comps = cinfo.output_components;
    if (expected == 0 || expected != comps) {
        jpeg_destroy_decompress(&cinfo);
        fclose(f);
        return IV_JPEG_BAD_FILE;
    }

    uint32_t w = cinfo.output_width;
    uint32_t h = cinfo.output_height;
    size_t row_bytes = (size_t)w * (size_t)comps;
    size_t need = row_bytes * (size_t)h;
    if (need > capacity) {
        jpeg_destroy_decompress(&cinfo);
        fclose(f);
        return IV_JPEG_TOO_SMALL;
    }

    // Scanlines go straight into the caller's buffer. Its rows are already
    // w * comps bytes - the same stride libjpeg emits - so there is no
    // intermediate row buffer and no per-pixel step. `output_scanline` is the
    // count read so far, so it indexes the row about to be filled.
    while (cinfo.output_scanline < h) {
        uint8_t *rows[1] = { &out[(size_t)cinfo.output_scanline * row_bytes] };
        jpeg_read_scanlines(&cinfo, rows, 1);
    }

    jpeg_finish_decompress(&cinfo);
    jpeg_destroy_decompress(&cinfo);
    fclose(f);

    info->width = w;
    info->height = h;
    info->color_space = color_space;
    return IV_JPEG_OK;
}