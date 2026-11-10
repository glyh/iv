---
id: 005
title: Install Qt Shader Tools (qsb)
labels: [wayfinder:task]
status: open
assignee:
blocked_by: []
---

## Question

Decision 12 compiles shaders to `.qsb` with `qsb` at build time. `qsb` is
not on this machine, and there is no shader to compile yet, but the viewport
ticket (008) cannot start without it.

`qt6-shadertools 6.12.0-1` is in the `extra` repository, so the work is one
`pacman -S qt6-shadertools`. This is AFK if that runs without a prompt;
otherwise it hands the human the single command.

## Done when

- `qsb --version` reports the version on this machine.
- The build-time dependency and its version are recorded in the map's Notes.
