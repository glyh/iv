# 13 - Repository: iv stands alone, qimgv is a reference

Status: decided

## The question

Where does iv live, and what is its relationship to the viewer it learned from?

## Decision

iv is its own repository. The qimgv fork - the reference implementation this
project's design was studied against - is **not** vendored, subclassed or built
here. It stays a read-only reference.

## Why

- iv picks its own toolchain cadence (Zig moves fast) without dragging a C++
  build along.
- The reference stays exactly as it was: nothing in iv depends on it at build or
  test time, and there is no "when do we delete the C++ tree" question.
- Its source remains available for consultation and, if ever needed, for
  comparison.

## Consequences

- A comparison against qimgv, if ever wanted, is cross-repo: pin a qimgv
  revision, build it there, compare outputs. Decision 11 leaves that as an
  optional manual tool, not a gate.
- Fixtures and expected outputs live in iv; nothing is shared.
- If the qimgv repository is removed despite being archived, only the research
  notes' provenance links are affected - no code path depends on it.
