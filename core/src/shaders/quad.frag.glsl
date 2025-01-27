#version 450

layout(location = 1) in vec2 quad_position;
layout(location = 0) out vec4 outColor;

const vec2 center = vec2(0.0, 0.0);

void main() {
    if (distance(quad_position, center) > 0.5) {
        discard;
    }
    const float opacity = 0.25;
    outColor = vec4(1.0, 1.0, 1.0, opacity);
}
