@vs vs
layout(binding=0) uniform vs_params {
    mat4 zoom;
    mat4 window_scale;
    mat4 untransform;
};

in vec2 position;
in vec2 p0;
in vec2 p1;
in vec4 color;
in float width;

out vec2 v_pos;
out vec2 v_p0;
out vec2 v_p1;
out vec4 v_color;
out float v_half_width;

void main() {
    vec2 dir = p1 - p0;
    float len = length(dir);
    vec2 tangent = len > 1e-6 ? dir / len : vec2(1.0, 0.0);
    vec2 normal = vec2(-tangent.y, tangent.x);

    float half_w = width * 0.5;
    float pad = half_w * 0.5;
    float ext = half_w + pad;

    vec2 base = mix(p0 - tangent * ext, p1 + tangent * ext, position.x);
    float side = (position.y * 2.0 - 1.0) * ext;
    vec2 vertex_pos = base + normal * side;

    mat4 t = untransform * zoom * window_scale;
    gl_Position = t * vec4(vertex_pos, 0.0, 1.0);

    v_pos = vertex_pos;
    v_p0 = p0;
    v_p1 = p1;
    v_color = color;
    v_half_width = half_w;
}
@end

@fs fs
in vec2 v_pos;
in vec2 v_p0;
in vec2 v_p1;
in vec4 v_color;
in float v_half_width;

out vec4 frag_color;

void main() {
    vec2 pa = v_pos - v_p0;
    vec2 ba = v_p1 - v_p0;
    float ba_dot = dot(ba, ba);
    float h = ba_dot > 1e-12 ? clamp(dot(pa, ba) / ba_dot, 0.0, 1.0) : 0.0;
    float dist = length(pa - ba * h);

    float aa = max(fwidth(dist), 1e-6);
    float alpha = 1.0 - smoothstep(v_half_width - aa * 0.5, v_half_width + aa * 0.5, dist);
    frag_color = vec4(v_color.rgb, v_color.a * alpha);
}
@end

@program line vs fs
