@header const m = @import("../math.zig")
@ctype mat4 m.Mat4

@vs vs

// Uniform block
layout(binding = 0) uniform vs_params {
    mat4 zoom;
    mat4 window_scale;
    mat4 untransform;
};

in vec2 xy;
out vec2 quad_position;

void main() {
    mat4 t = untransform * zoom * window_scale;
    float k = zoom[0][0];
    float size = exp(log(k) * 0.01) / 300.0;

    float x = xy.x;
    float y = xy.y;
    // vec2 quad_pos[6] = vec2[](
    //         vec2(0, 0),
    //         vec2(1, 0),
    //         vec2(0, 1),
    //         vec2(0, 1),
    //         vec2(1, 0),
    //         vec2(1, 1)
    //     );
    // vec2 qp = quad_pos[gl_VertexIndex] - 0.5;
    vec2 qp = xy - 0.5;
    vec4 pos = vec4(x, y, 1.0, 1.0) + vec4(qp * size, 0.0, 0.0);
    gl_Position = t * pos;
    quad_position = qp;
}
@end

@fs fs
in vec2 quad_position;
out vec4 frag_color;

void main() {
    const vec2 center = vec2(0.0, 0.0);
    if (distance(quad_position, center) > 0.5) {
        discard;
    }
    float opacity = 0.25;
    frag_color = vec4(1.0, 1.0, 1.0, opacity);
}
@end

@program quad vs fs
