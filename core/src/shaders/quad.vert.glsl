#version 450

layout(set = 0, binding = 0) readonly buffer XValues {
    float x_values[];
};

layout(set = 0, binding = 1) readonly buffer YValues {
    float y_values[];
};

layout(set = 1, binding = 0) uniform Uniforms {
    mat4 zoom;
    mat4 window_scale;
    mat4 untransform;
} uni;

layout(location = 1) out vec2 quad_position;

void main() {
    float x = x_values[gl_InstanceIndex];
    float y = y_values[gl_InstanceIndex];
    mat4 t = uni.untransform * uni.zoom * uni.window_scale;
    float k = uni.zoom[0][0];
    float size = exp(log(k) * 0.01) / 300.0;

    const vec2 quad_pos[6] = vec2[](
        vec2(0, 0),
        vec2(1, 0),
        vec2(0, 1),
        vec2(0, 1),
        vec2(1, 0),
        vec2(1, 1)
    );

    vec2 qp = quad_pos[gl_VertexIndex] - 0.5;
    vec4 xy = vec4(x, y, 1.0, 1.0) + vec4(qp * size, 0.0, 0.0);
    gl_Position = t * xy;
    quad_position = qp;
}
