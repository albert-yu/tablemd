@vs vs
layout(binding=0) uniform vs_params {
    mat4 zoom;
    mat4 window_scale;
    mat4 untransform;
};

in vec2 position;

// instance attributes
in vec2 instance_position;
in vec2 glyph_size;
in vec2 tex_offset;
in vec2 tex_size;
in vec4 color;
in float pixel_scale;

out vec2 v_tex_coords;

void main() {
    mat4 t = untransform * zoom * window_scale;
    vec2 scaled_pos = (position * glyph_size + instance_position) * pixel_scale;
    gl_Position = t * vec4(scaled_pos, 0.0, 1.0);
    v_tex_coords = position * tex_size + tex_offset;
}
@end

@fs fs
layout(binding=0) uniform texture2D tex;
layout(binding=0) uniform sampler smp;

in vec2 v_tex_coords;
out vec4 frag_color;

void main() {
    vec4 sampled = texture(sampler2D(tex, smp), v_tex_coords);
    frag_color = vec4(1.0, 1.0, 1.0, sampled.r);
}
@end

@program text vs fs

