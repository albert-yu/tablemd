@vs vs
layout(binding=0) uniform vs_params {
    mat4 zoom;
    mat4 window_scale;
    mat4 untransform;
};

in vec2 position;
in vec4 color;

out vec4 v_color;

void main() {
    mat4 t = untransform * zoom * window_scale;
    gl_Position = t * vec4(position, 0.0, 1.0);
    v_color = color;
}
@end

@fs fs
in vec4 v_color;
out vec4 frag_color;

void main() {
    frag_color = v_color;
}
@end

@program line vs fs
