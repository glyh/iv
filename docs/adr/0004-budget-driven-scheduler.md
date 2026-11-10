# The memory budget is in bytes and governs lazy versus eager work

Status: accepted

The core's interface is request-based, but a scheduler inside the core decides
whether hinted work runs eagerly or only on demand, against a user-set budget in
**bytes** that covers retained artifacts *and* in-flight decode buffers. The
shell supplies hints; the core decides execution. Full reasoning:
`../design/02-core-interface.md`.

## Considered options

- **Pure request/response**: rejected because all scheduling then lives in the
  shell and the budget cannot be enforced centrally.
- **A full libvips-style pull pipeline**: rejected for v1 as a much larger design
  to debug; it remains available as a layer above this one.
- **A push/prefetch pipeline**: rejected because prediction is shell knowledge;
  the shell supplies hints instead.

## Consequences

- The core owns a thread pool, a priority queue and a byte accountant
  (decision 08).
- Prefetch must be cancelable and re-targetable at any moment.
- One request may produce several results over time (preview, then final).
