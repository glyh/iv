---
id: 003
title: Land the decode registry and the JPEG backend
labels: [wayfinder:task]
status: open
assignee:
blocked_by: [001, 002]
---

## Question

Land `src/core/decode/`: the backend registry of decision 03 and its first
real backend, JPEG.

- A `Backend` carries a name, the formats it claims, a probe over the first
  bytes, and a decode entry taking bytes plus the size contract settled in
  ticket 002.
- The registry is asked in one documented, fixed order. Decision 03's ordering
  rule (a RAW backend would be asked before a generic TIFF one) is written down
  now even though neither exists yet.
- The probe has three outcomes, not two: decoded; recognized but the data is
  broken (stop, do not try the next backend); not recognized (try the next).
- The JPEG backend is bound the way ticket 001 decided.
- One committed fixture and one smoke test asserting dimensions, format and no
  crash (decision 11). The fixture is small and its licence is stated in the
  test.

`src/core/root.zig` re-exports the module, and its TODO loses the decode
bullet.

## Done when

- `zig build test` covers the three probe outcomes and the JPEG fixture.
- A caller goes from a `[]const u8` file image to a `Bitmap` in one call,
  with no UI toolkit and no display.
- The decode entry points carry the ticket-002 contract in their doc comments.
