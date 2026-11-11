#version 460 core

layout(location = 0) in vec2 pos;
layout(location = 1) in vec2 uv;

uniform vec2 scale;

out vec2 v_uv;

void main() {
    v_uv = uv;
    gl_Position = vec4(pos * scale, 0.0, 1.0);
}
