/* quad vertex shader */
@header const m = @import("../math.zig")
@ctype mat4 m.Mat4

@vs vs
layout(binding=0) uniform vs_params {
    mat4 zoom;
    mat4 window_scale;
    mat4 untransform;
};

in vec2 position;
in vec4 color0;
in vec2 instance_position;
out vec2 uv;
out vec4 color;

void main() {
    // get transform from uniforms
    mat4 t = untransform * zoom * window_scale;
    // size to shrink non-linearlly
    float k = zoom[0][0];
    float size = exp(log(k) * 0.01) / 300.0;

    // vertex position
    vec2 qp = vec2(position.x, position.y);
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
