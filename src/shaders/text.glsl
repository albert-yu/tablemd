@vs vs
layout(binding=0) uniform vs_params {
    mat4 zoom;
    mat4 window_scale;
    mat4 untransform;
};

in vec2 position;
in vec2 tex_coords;

out vec2 v_tex_coords;

void main() {
    mat4 t = untransform * zoom * window_scale;
    gl_Position = t * vec4(position, 0.0, 1.0);
    v_tex_coords = tex_coords;
}
@end

@fs fs
layout(binding=0) uniform texture2D tex;
layout(binding=0) uniform sampler smp;

in vec2 v_tex_coords;
out vec4 frag_color;

void main() {
    frag_color = texture(sampler2D(tex, smp), v_tex_coords);
}
@end

@program text vs fs

