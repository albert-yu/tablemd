/* quad vertex shader */
@header const m = @import("../math.zig")
@ctype mat4 m.Mat4

@vs vs
layout(binding=0) uniform vs_params {
    mat4 zoom;
    mat4 window_scale;
    mat4 untransform;
};

in vec3 position;
in vec4 color0;
in vec3 instance_position;
out vec2 uv;
out vec4 color;

void main() {
    // get transform from uniforms
    mat4 t = untransform * zoom * window_scale;
    // size to shrink non-linearlly
    float k = zoom[0][0];
    float size = exp(log(k) * 0.01) / 300.0;

    // vertex position
    vec2 qp = vec2(position.x, position.y) - 0.5;
    vec4 xy = vec4(instance_position.x, instance_position.y, 1.0, 1.0) + vec4(qp * size, 0.0, 0.0);

    // return values
    gl_Position = t * xy; // vertex position
    uv = qp;
    color = color0;
}
@end

/* quad fragment shader */
@fs fs
in vec2 uv;
in vec4 color;
out vec4 frag_color;

void main() {
    vec2 center = vec2(0.0, 0.0);
    float dist = distance(uv, center);
    float radius = 0.5;
    if (dist > radius) {
        discard;
    }

    frag_color = color;
}
@end

/* quad shader program */
@program quad vs fs


// @vs vs

// // Uniform block
// layout(binding = 0) uniform vs_params {
//     mat4 zoom;
//     mat4 window_scale;
//     mat4 untransform;
// };

// in vec2 xy;
// out vec2 quad_position;

// void main() {
//     mat4 t = untransform * zoom * window_scale;
//     float k = zoom[0][0];
//     float size = exp(log(k) * 0.01) / 300.0;

//     float x = xy.x;
//     float y = xy.y;
//     // vec2 quad_pos[6] = vec2[](
//     //         vec2(0, 0),
//     //         vec2(1, 0),
//     //         vec2(0, 1),
//     //         vec2(0, 1),
//     //         vec2(1, 0),
//     //         vec2(1, 1)
//     //     );
//     // vec2 qp = quad_pos[gl_VertexIndex] - 0.5;
//     vec2 qp = xy - 0.5;
//     vec4 pos = vec4(x, y, 1.0, 1.0) + vec4(qp * size, 0.0, 0.0);
//     gl_Position = t * pos;
//     quad_position = qp;
// }
// @end

// @fs fs
// in vec2 quad_position;
// out vec4 frag_color;

// void main() {
//     const vec2 center = vec2(0.0, 0.0);
//     if (distance(quad_position, center) > 0.5) {
//         discard;
//     }
//     float opacity = 0.25;
//     frag_color = vec4(1.0, 1.0, 1.0, opacity);
// }
// @end

// @program quad vs fs
