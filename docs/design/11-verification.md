# 11 - Verification: simple unit tests

Status: decided

## The question

How do we know iv is correct?

## Decision

Verification is **unit tests only**:

- Constructed inputs whose expected output is computed by hand, covering the
  pure-Zig parts: bitmap, imageops, signal, cache accounting, budget eviction.
- A smoke test per decode backend: a committed fixture, asserting dimensions,
  format and no crash.
- **No differential harness** against qimgv as a gate.
- **No conformance corpora** as a gate.

## Why

A comparison against qimgv (its own repository, decision 13) was judged too
costly to maintain for the value it returns at this stage. The core's own logic
can be kept honest with unit tests, and the decoder libraries' own test suites
remain the authority for the formats themselves.

## Consequences and accepted risk

- Unit tests **cannot show** "iv renders what qimgv renders". A regression in
  real-image output would surface only by inspection or by a hand-run comparison
  against qimgv.
- The risk is concentrated in the **adapters** - argument handling, format
  dispatch, orientation, colour - not in the decoder libraries.
- Adding a differential or conformance harness later is cheap: keep decode
  deterministic and its output comparable, and the harness can be added without
  changing the architecture.
- If a rendering difference is ever reported, writing that comparison is a
  one-off, not a redesign.
