# Instructions for this repository

## What this is

`iv` is a from-scratch Zig image viewer. Its architecture was decided before the
first line of code. The decision records are in `docs/design/`, the ADRs in
`docs/adr/` and the vocabulary in `CONTEXT.md`; the invariants below are the
contract. Code that contradicts them is a bug unless a new decision supersedes
them.

## Toolchain

- Zig 0.17.0
- `zig build` - build
- `zig build test` - run all tests
- `zig build run` - run the app

## Workflow (non-negotiable)

1. **Every change arrives as a pull request.** Never commit directly to the
   default branch.
2. **Commits are atomic**: one semantic change each. Prefer several small commits
   over one large one, and keep a commit under roughly 400 changed lines unless
   it is mechanical.
3. **No commit may add something a later commit in the same PR removes.** Fold
   fix-ups into the commit that introduced the code.
4. **When a PR is ready, ask the user for review and stop.** Do not merge it.
5. Never force-push a branch that has been reviewed; add commits instead.

## Architecture invariants

- The **core** (`src/core/`) is Qt-free and owns only the pixel pipeline:
  decode, transform, thumbnail, cache. Directories, settings, video and UI are
  the shell.
- Decode is a **registry of backends**, one module per library; still images
  only. An absent backend is simply absent.
- Pixels are 8-bit gray/RGB/RGBA with **straight alpha**; premultiply only
  inside the resampler.
- Scaling: area prefilter above 2x, bicubic otherwise, `@Vector` kernels.
- Colour: an lcms2 transform step that is a no-op when source and destination
  agree; source pixels and profile are preserved.
- Cache: the freedesktop thumbnail contract on disk; a byte-budgeted,
  per-pixel-buffer LRU with pinning in memory. The budget is in bytes and covers
  in-flight decode buffers too.
- Concurrency: the core owns a fixed pool with two priority bands; cancellation
  is cooperative, checked at step boundaries.
- Every event has exactly one consumer: an app-internal event is a plain Zig
  callback, and a worker that must reach the Qt main thread goes through the
  binding's `Threading` helpers. An event with two consumers is a new decision to
  record.
- Errors are values. Nothing in the core panics, and no `unreachable` sits on a
  path that external input can reach.
- Verification is unit tests (`zig build test`) that need no display.

## Conventions

- Commit subjects: `scope: imperative summary` (for example,
  `core: add the area prefilter`).
- Keep the core testable without a Qt install; commit any test fixture.
- Add a term to `CONTEXT.md` when it is introduced or sharpened. Add an ADR only
  when a decision is hard to reverse, surprising, and the result of a real
  trade-off.

### Plain technical English

Write the obvious term. Do not coin metaphors for things that already have plain
names: no "currency" for a pixel type, no "wheel" for a primitive, no "hot core",
no "multicast" for a subscriber list. A term is allowed only if `CONTEXT.md`
defines it; add the definition before the word is used. A term used in code or
docs that is not in `CONTEXT.md` is a bug; fix the term or add the definition.

### Known gaps live in the code

A gap that a later agent must know about goes in the source as a `TODO` comment,
not only in the PR description: the next agent reads the code, not the PR. A
`TODO` names the gap and the decision or ADR that settles it.
