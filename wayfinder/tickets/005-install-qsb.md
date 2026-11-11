---
id: 005
title: Install Qt Shader Tools (qsb)
labels: [wayfinder:task]
status: closed
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

## Answer

**Moot.** Decision 12 moved the shell to GTK4 and the viewport to `GtkGLArea`
on OpenGL, so shaders are GLSL compiled in the shell's own GL context. There is
no `.qsb` step, `qt6-shadertools` is not a build dependency, and ticket 008 no
longer waits on this.