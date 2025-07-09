@vs vs
layout(binding=0) uniform vs_params {
    mat4 zoom;
    mat4 window_scale;
    mat4 untransform;
};

in vec2 position;
in vec2 tex_coords;
in vec2 instance_position;
in vec2 glyph_size;
in vec2 tex_offset;
in vec2 tex_size;
in vec4 color;

out vec2 v_tex_coords;
out vec4 v_color;

void main() {
    vec2 vertex_pos = instance_position + position * glyph_size;
    mat4 t = untransform * zoom * window_scale;
    gl_Position = t * vec4(vertex_pos, 0.0, 1.0);
    
    // Calculate texture coordinates from atlas offset and size
    v_tex_coords = tex_offset + tex_coords * tex_size;
    v_color = color;
}
@end

@fs fs
layout(binding=0) uniform texture2D tex;
layout(binding=0) uniform sampler smp;

in vec2 v_tex_coords;
in vec4 v_color;
out vec4 frag_color;

void main() {
    float alpha = texture(sampler2D(tex, smp), v_tex_coords).r;
    frag_color = vec4(v_color.rgb, v_color.a * alpha);
}
@end

@program text vs fs