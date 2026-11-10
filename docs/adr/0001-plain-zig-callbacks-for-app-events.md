# App-internal signals become plain Zig callbacks, with a Zig subscriber list when needed

Status: accepted

Qt signals are the natural way to broadcast an app-internal event, but libqt6zig
cannot declare a new Qt signal on a Zig subclass, and a moc'd C++ shim would bring
back the build iv exists to avoid. The reference viewer has 60 headers declaring
`signals:` and 394 `connect(` sites, so this is not a corner of the design. An
app-internal event is therefore a plain Zig callback, and where one event has
several consumers iv uses its own single-threaded subscriber list
(`src/core/signal.zig`) instead of a Qt signal or a C++ shim. Qt's own signals
(`QPushButton::clicked`, `QTimer::timeout`, ...) are still consumed through the
binding's `onSignal`.

## Considered options

- **Qt signals via a moc'd C++ shim per signal-bearing class**: exact semantics,
  but moc and C++ come back.
- **A hand-rolled subscriber list at each 1:N site**: works, but duplicates
  lifetime and iteration code; one generic `Signal` is enough.

## Consequences

- No `Q_OBJECT`, no moc, no C++ subclass of our own.
- Auto-disconnect is gone: a subscriber clears its handler explicitly
  (`Signal.disconnect`).
- The subscriber list is single-threaded. Cross-thread delivery is not provided; a
  worker that produces results on another thread hands them back explicitly.
