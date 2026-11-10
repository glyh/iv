# 02 - Core interface: requests, with a budget-driven scheduler

Status: decided (grilled 2026-11)

## The question

Who decides what the core computes - the shell by explicit requests, or the core
by demand? And should work happen lazily or ahead of time?

## The options

1. **Request/response only** - the shell calls concrete operations; the core runs
   them and returns. Simple, testable, but all scheduling lives in the shell.
2. **Demand-driven pull pipeline** - the shell describes the result; the core
   evaluates lazily and reuses intermediates (libvips). Best memory behaviour,
   much larger design, harder to debug first.
3. **Push/prefetch pipeline** - the shell streams the files it expects next; the
   core keeps them decoded ahead of use. Great browsing feel, but prediction is
   pushed into the shell.
4. **(chosen) Requests + a demand-driven scheduler inside the core + a user-set
   memory budget that decides lazily vs eagerly, with the shell supplying hints.**

## Decision

The interface is request-based, but the core owns execution policy:

- The shell makes explicit requests - `decode(path, max_w, max_h)`,
  `scale(bitmap, w, h)`, `thumbnail(path, size)` - and may attach a **hint**:
  "these paths are likely next, in this order".
- The core keeps a **memory budget** that the user sets. Against that budget a
  scheduler decides, per piece of work, whether to compute it now (eager), only
  when asked (lazy), or to drop it and re-derive later.
- With headroom, the core eagerly prefetches hinted work. Under pressure it
  falls back to lazy: compute only what the current request needs and retain as
  little as possible.
- The budget is a first-class, user-visible setting, not a hidden constant.

Internally this is a small demand-driven graph per request (decode -> optional
transform -> requested size), so one decode can feed several sizes without the
shell ever seeing a graph.

## Why

- The reuse benefit of option 2 is real and does not require exposing a graph:
  "one decode feeding a thumbnail and a viewport" can be arranged inside the
  core while the shell still asks concrete questions.
- Eagerness is what makes browsing feel instant, but only when memory allows.
  Making it budget-driven turns a fixed policy into a knob the user controls.
- The knowledge needed to predict (folder order, which way the user is moving)
  lives in the shell; the decision about how much memory to spend does not. Each
  stays where it belongs.

## Consequences

- **This revises one argument from decision 01**, not its boundary: the *hints*
  are the shell's, the *execution policy* is the core's. The core still never
  lists a directory; it is handed paths and hints.
- The core gains a scheduler and a budget accountant. Both are testable with no
  GUI: feed requests and hints, assert what was decoded, evicted, or deferred.
- The budget must cover **cached decoded frames and in-flight decode buffers**.
  A progressive JPEG or a 100-megapixel scan can allocate hundreds of megabytes
  during a single decode, so a limit enforced only on the cache can be blown by
  one request.
- Prefetch must be cancelable and re-targetable: the user can reverse direction
  at any moment, and stale eager work has to be dropped cheaply.

## Budget shape (decided)

- **Unit: bytes.** It covers the cached decoded frames *and* the in-flight decode
  buffers of work currently running.
- **Default**: a small fraction of system RAM (working default 10%, with a hard
  cap), stored as a user-editable setting rather than a constant.
- **Enforcement**: the core accounts for its allocations; over budget it evicts
  least-recently-used decoded frames, and eager prefetch runs only while
  headroom remains.
- **Why bytes, not images**: a count-of-images budget prices a 1-megapixel icon
  and a 500-megapixel scan the same. Bytes are the only unit that stays honest
  across formats, sizes and bit depths.
- **Why in-flight buffers count**: one progressive JPEG or a very large scan can
  allocate hundreds of megabytes *during* a single decode, so a cache-only
  ceiling is a limit that one request can blow.
- **Testability**: set the budget to N bytes in a unit test and the eviction
  order becomes deterministic and assertable.

## Open sub-questions

- What the user sees when pressure forces laziness: a lower-resolution preview
  now, or just a slower full one.
