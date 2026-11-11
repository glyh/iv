# App-internal events are plain Zig callbacks

Status: accepted (revised 2026-11: one consumer per event, restated for GTK4)

GTK signals are the natural way to broadcast an app-internal event, but
declaring a new one means declaring a new GObject type - `G_DECLARE_FINAL_TYPE`,
a class init, a signal registration - and a GObject subclass of our own. That is
exactly the GObject boilerplate this project exists to avoid, and the reference
viewer has 60 headers declaring `signals:` and 427 `connect(` sites, so this is
not a corner of the design.

An app-internal event therefore gets a plain Zig callback: **one event, one
consumer**. GTK's own signals (`GtkButton::clicked`, `GtkGLArea::render`,
`GtkWidget::destroy`, ...) are still consumed through `g_signal_connect`; a
worker that must reach the GTK main thread goes through `g_main_context_invoke`
(or `g_idle_add_full`), which marshals a callback onto that thread.

## Considered options

- **A new GObject signal per app-internal event**: exact semantics, but a GType
  declaration and a widget subclass come back with it.
- **A generic subscriber list for an event with several consumers**: considered
  and rejected. No design document names an event with more than one consumer,
  and the rule below makes one unnecessary.

## Consequences

- No `G_DECLARE_FINAL_TYPE`, no GObject subclass of our own, no C++.
- **Every event has exactly one consumer.** An event that needs two is a new
  decision to record, not a reason to keep a dormant list around.
- There is no auto-disconnect to rely on, and none to lose: the consumer owns
  the callback and clears it.
- Cross-thread delivery is not part of this decision; it is
  `g_main_context_invoke`'s job, and it is the only such hop the shell makes.

## Revision

2026-11: amended - every event has exactly one consumer. The original text
proposed a single-threaded subscriber list "when one event has several
consumers"; no such event was ever named, so the list was not implemented.
2026-11: restated for GTK4 after decision 12 moved the shell off Qt.