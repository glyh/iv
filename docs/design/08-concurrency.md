# 08 - Concurrency and cancellation: a pool owned by the core

Status: decided

## The question

Who owns the threads, how much work runs at once, and how is in-flight work
abandoned when the user moves on?

## Context

Decode, scale and colour transform are slow enough to stall a UI thread, so they
need a worker pool. Too many threads thrash the CPU and multiply the in-flight
decode buffers; decodes are CPU-bound, so the pool size follows the core count.

Cancellation is largely **cooperative**: libjpeg-turbo cannot stop mid-decode,
while libjxl and libheif progressive decoding can. The practical rule is to check
"is this still wanted?" at step boundaries and discard the result, freeing its
memory immediately.

Zig 0.17 provides `std.Thread.spawn` and a new `std.Io` with structured
concurrency (`Group.async`/`await`), `Cancelable` errors, `Semaphore`,
`RwLock` and `Mutex`.

## The options

1. **The core owns a fixed pool**, a priority queue, and step-boundary
   cancellation; tests inject a synchronous executor.
2. A thread per request.
3. No threads in the core; the shell owns them.

## Decision

- The core owns a **fixed-size worker pool**, sized from the CPU count.
- Work is **prioritised**: user-visible requests first, eager/prefetch work last.
- Eager work is **dropped wholesale** as soon as a user request arrives.
- Cancellation is **cooperative and checked at step boundaries**: between decode,
  transform, scale and cache write. A decode that cannot be interrupted is
  allowed to finish, and its result is discarded and freed immediately.
- Tests inject a **synchronous executor**, so the same request path runs
  single-threaded and deterministically.
- The budget accountant is thread-safe; every worker touches it.

## Why

- Decision 02 put the scheduler in the core, so the threads must be there too;
  option 3 would leave the scheduler unenforceable and duplicate its logic in the
  shell.
- Option 2 makes a 5000-image grid spawn thousands of threads.
- A fixed pool with two priority bands bounds the number of simultaneous decode
  buffers, which the byte budget depends on.
- The synchronous executor is what keeps "test without a GUI" true.

## Consequences

- The core has a lifecycle (start workers, drain, stop) and a shutdown path that
  must not leak pinned pixel buffers.
- Some decoders waste work that cannot be cancelled; the design accepts that and
  reclaims the memory.
- Priority inversion and starvation are possible if the eager band is ever given
  equal priority; the two-band rule has to stay.
