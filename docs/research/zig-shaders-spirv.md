# Zig-authored shaders: SPIR-V, and whether OpenGL takes it

Spiked 2026-11-11 on this machine (Zig 0.17.0, GTK 4.24.1, Mesa 26.2.6-arch1.1,
libepoxy 1.5.10, spirv-tools installed). Every command below was run; the probe
projects are throwaway and live under `/tmp/spirvprobe`.

## The question

The viewport's shaders are 20 lines of GLSL in `src/shell/shaders/`. Writing
them in Zig instead - compile to SPIR-V at build time, hand the module to the
GL area - would keep the whole program in one language and type-check varyings
and uniforms. Is that reachable in Zig 0.17, and does it survive contact with
`GtkGLArea` on desktop GL?

The two starting links are both dead ends for 0.17. The gist
(`alichraghi/cc4b1db0`) is a GLSL-to-Zig mapping note written before
`@SpirvType` existed; its code says images "can't be implemented in a good form
yet" and no longer compiles, because `std.gpu` is gone. The ziggit thread has no
SPIR-V answer at all - one reply recommends wgpu-native.

## 1. Zig 0.17 has the graphics stages, not just compute

`std/lang.zig:380-386` declares the execution models as calling conventions:

```zig
spirv_device,
spirv_vertex,
spirv_kernel: SpirvKernelOptions,      // x, y, z workgroup size
spirv_fragment: SpirvFragmentOptions,  // pixel_centered_integer, depth_assumption
spirv_task: SpirvKernelOptions,
spirv_mesh: SpirvMeshOptions,
```

Stage IO is explicit. `@extern` takes a decoration (`std/lang.zig:1222`):

```zig
pub const Decoration = union(enum) { location: u32, flat: u32, descriptor: Descriptor };
```

and `@SpirvType(.{ .image = ... })` / `.sampled_image` build the opaque types
that `std.spirv` (`std/spirv.zig`, 272 lines) then samples with
`imageSampleImplicitLod`. `std.spirv` also holds `position_out`, `frag_coord`,
`point_coord`, `frag_depth`, `vertex_index`.

## 2. The quad's shaders, rewritten in Zig

`/tmp/spirvprobe/quad3.zig`, abridged to the shape that matters:

```zig
const tex = @extern(*addrspace(.constant) const SampledImage, .{
    .name = "tex",
    .decoration = .{ .descriptor = .{ .set = 0, .binding = 0 } },
});
const params = @extern(*addrspace(.uniform) const Params, .{   // Params = extern struct { scale: @Vector(2, f32) }
    .name = "params",
    .decoration = .{ .descriptor = .{ .set = 0, .binding = 1 } },
});
const pos    = @extern(*addrspace(.input)  @Vector(2, f32), .{ .name = "pos", .decoration = .{ .location = 0 } });
const uv_in  = @extern(*addrspace(.input)  @Vector(2, f32), .{ .name = "uv",  .decoration = .{ .location = 1 } });
const uv_out = @extern(*addrspace(.output) @Vector(2, f32), .{ .name = "uv",  .decoration = .{ .location = 0 } });
const color  = @extern(*addrspace(.output) @Vector(4, f32), .{ .name = "color", .decoration = .{ .location = 0 } });

export fn vmain() callconv(.spirv_vertex) void {
    uv_out.* = uv_in.*;
    std.spirv.position_out.* = .{ pos.*[0] * params.scale[0], pos.*[1] * params.scale[1], 0, 1 };
}

export fn fmain() callconv(.{ .spirv_fragment = .{} }) void {
    color.* = std.spirv.imageSampleImplicitLod(tex, uv_in.*);
}
```

Two quirks of the language surface, both hit and both cheap once known:

- Samplers go in `addrspace(.constant)` (SPIR-V `UniformConstant`).
  `addrspace(.uniform)` is `Uniform` storage class, which is struct-only and
  rejects embedding an opaque type: *"extern in 'uniform' address space must be
  a single-item pointer to a struct"*.
- A uniform block is an `extern struct` in `addrspace(.uniform)`; the backend
  emits `Block`, `Offset` per member and `ArrayStride` itself (measured:
  `OpMemberDecorate %_struct 0 Offset 0`, `OpDecorate %params Binding 1`).

```
$ zig build-obj quad3.zig -target spirv32-vulkan -femit-bin=quad3.spv
$ ls -l quad3.spv           # 2224 bytes, two OpEntryPoint, Version 1.0
$ spirv-val --target-env opengl4.5 quad3.spv && echo val ok
val ok
```

No `-fno-llvm` and no LLVM involvement were needed; the self-hosted backend
picks itself for a `spirv*` target. **The module is SPIR-V 1.0** (header
`07230203 00010000`, `spirv-dis` agrees: `Version: 1.0`), which is exactly what
`ARB_gl_spirv` requires - no version-word patching.

## 3. Loading it into GL: this actually links

`GL_ARB_gl_spirv` is present on this machine (`GL 4.6 core, Mesa 26.2.6`,
`epoxy_has_gl_extension("GL_ARB_gl_spirv") = 1`). `/tmp/spirvprobe/glspirv.c`
is an EGL pbuffer harness that does the whole load:

```
glShaderBinary(1, &vs, GL_SHADER_BINARY_FORMAT_SPIR_V, blob, len);
glSpecializeShader(vs, "vmain", 0, NULL, NULL);
glShaderBinary(1, &fs, GL_SHADER_BINARY_FORMAT_SPIR_V, blob, len);
glSpecializeShader(fs, "fmain", 0, NULL, NULL);
glLinkProgram(prog);
```

```
vertex 'vmain' from module: OK
fragment 'fmain' from SAME module: OK
link: OK
glGetError after draw = 0x0
```

Two useful consequences: **one `.spv` serves both stages** (specialise it once
per stage with the entry-point name), and the module validates for
`--target-env vulkan1.2` as well, so the same artifact would survive a move to
Vulkan.

## 4. The three quirks

**Use `spirv32`, never `spirv64-vulkan`.** That target emits
`OpMemoryModel PhysicalStorageBuffer64` plus
`SPV_KHR_physical_storage_buffer`, and Mesa **segfaults inside
`glLinkProgram`** on the result - no GL error, no driver message, a core dump.
`spirv32-vulkan`, `spirv32-opengl` and `spirv64-opengl` all emit
`Logical GLSL450` and link cleanly. `spirv32-vulkan` also emits
`OriginUpperLeft`, `spirv32-opengl` emits `OriginLowerLeft`; Mesa accepted both,
and which one other drivers want is unverified.

**Reflection by name is gone.** In SPIR-V mode Mesa reports empty uniform
names, so the host cannot look anything up:

```
active uniforms=2
  [0] name='' location=-1 type=0x8b50
  [1] name='' location=-1 type=0x8b5e
glGetUniformLocation("tex")=-1
glUniform1i(0,0) err=0x502        # GL_INVALID_OPERATION
```

Sampler units and block bindings come from the `Binding` decoration alone, so
the shell has to share binding numbers with the shader as constants instead of
looking uniforms up by name. A shader that writes `frag_depth` is also not
expressible yet: Vulkan validation wants `DepthReplacing` and the
`.spirv_fragment` options carry only `depth_assumption`.

**Driver coverage is a Mesa fact, not a GL fact.** `ARB_gl_spirv` is supported
by Mesa (tested) and is impossible on macOS, which caps at GL 4.1. NVIDIA and
AMD proprietary drivers were **not** tested; do not assume them.

## 5. What it would cost, and the decision

Adopting it for the viewport is a contained change: the same two shaders in Zig,
`zig build` emitting `.spv` with `-target spirv32-vulkan`, and a loader branch
that uses `glShaderBinary` + `glSpecializeShader` when
`GL_ARB_gl_spirv` is present and falls back to the committed GLSL otherwise -
roughly 60 lines in `src/shell/`. Against that: a load path that is Mesa-only
today, reflection traded for hand-shared binding constants, and a target triple
to pin.

**Deferred until it is mature** (decided 2026-11-11, recorded in decision 12).
The GPU's only job here is one textured quad - a Zig shader would be
type-checked code with nothing to type-check - and the scaling that would want
compute stays on the CPU in the core (decision 06). Revisit when a shader
arrives with real logic (annotation overlays, a fragment-side colour transform),
or when `ARB_gl_spirv` is universal and the `spirv64-vulkan` crash, the
reflection loss and the missing `DepthReplacing` are gone.

## Not measured

- Whether the Zig-emitted pair draws the right pixels. Only specialisation,
  link and `glGetError` were checked.
- NVIDIA, AMD or any non-Mesa GL driver.
- `glEnable(GL_SPIRV_EXTENSIONS_ARB)` and offline `glslangValidator` acceptance
  of Zig's output - neither is needed with the pattern above.
