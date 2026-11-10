---
id: 002
title: What a decode backend promises about size
labels: [wayfinder:grilling]
status: open
assignee:
blocked_by: []
---

## Question

Decision 03 says "decode at the maximum size, never decode whole and shrink",
but that is not a promise every library can keep: libjpeg-turbo scales only by
eighths (1/8 up to 2x), and libpng offers no general scale factor, only
row-level control. What exactly does
a decode request ask for, what does a backend guarantee, and who finishes the
fit?

Settle, precisely:

- Is `max_w`/`max_h` an upper bound on the result, a target, or a hint?
- When the library can only land up to 2x larger than asked (1/8 granularity),
  is an oversized-but-close result acceptable, and who records the difference?
- When a library cannot decode small at all, may a backend decode whole and
  hand a full-size bitmap back, with the registry scaling it down — or is that
  the one thing the contract forbids?
- Does the request carry the final display size so a backend can pick its
  ratio, and what does the caller then do with the result?
- Does the registry guarantee a postcondition (the result fits `max`) even
  when a backend overshoots?

The recommendation to grill against: `max` is an upper bound on the
*request*; a backend returns the smallest decode that still covers it (never
below); the result records requested and delivered size; the registry does
**not** promise the postcondition, and the caller or the viewport completes the
fit. This is a ticket because ticket 003 cannot be written without its answer.

## Done when

- The contract is written into decision 03 (or a new ADR) and into the doc
  comments of the decode entry points, so ticket 003 can be written against it.
- Every sub-question above has a stated answer, not a lean.
