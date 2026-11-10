# App-internal events are plain Zig callbacks

Status: accepted (revised 2026-11: one consumer per event)

Qt signals are the natural way to broadcast an app-internal event, but libqt6zig
cannot declare a new Qt signal on a Zig subclass, and a moc'd C++ shim would bring
back the build iv exists to avoid. The reference viewer has 60 headers declaring
`signals:` and 427 `connect(` sites, so this is not a corner of the design.

An app-internal event therefore gets a plain Zig callback: **one event, one
consumer**. Qt's own signals (`QPushButton::clicked`, `QTimer::timeout`, ...)
are still consumed through the binding's `onSignal`; a worker that must reach the
Qt main thread goes through the binding's `Threading` helpers, which marshal a
callback onto that thread.

## Considered options

- **Qt signals via a moc'd C++ shim per signal-bearing class**: exact semantics,
  but moc and C++ come back.
- **A generic subscriber list for an event with several consumers**: considered
  and rejected. No design document names an event with more than one consumer,
  and the rule below makes one unnecessary.

## Consequences

- No `Q_OBJECT`, no moc, no C++ subclass of our own.
- **Every event has exactly one consumer.** An event that needs two is a new
  decision to record, not a reason to keep a dormant list around.
- There is no auto-disconnect to rely on, and none to lose: the consumer owns the
  callback and clears it.
- Cross-thread delivery is not part of this decision; it is the binding's
  `Threading` job.

## Revision

2026-11: amended — every event has exactly one consumer. The original text
proposed a single-threaded subscriber list "when one event has several
consumers"; no such event was ever named, so the list was not implemented.
