@header const m = @import("../math.zig")
@ctype mat4 m.Mat4

@vs vs

layout(binding=0) uniform vs_params {
    mat4 zoom;
    mat4 window_scale;
    mat4 untransform;
};

in vec4 position;
in vec2 texcoord0;
in vec4 color0;
in float psize;
out vec4 uv;
out vec4 color;

void main() {
    mat4 t = untransform * window_scale * zoom;
    gl_Position = position;
    #ifndef SOKOL_WGSL
    gl_PointSize = psize;
    #endif
    uv = t * vec4(texcoord0, 0.0, 1.0);
    color = color0;
}
@end

@fs fs
layout(binding=0) uniform texture2D tex;
layout(binding=0) uniform sampler smp;
in vec4 uv;
in vec4 color;
out vec4 frag_color;
void main() {
    frag_color = vec4(1.0, 1.0, 1.0, texture(sampler2D(tex, smp), uv.xy).r) * color;
}
@end

@program text vs fs
