@header const m = @import("../math.zig")
@ctype mat4 m.Mat4

@vs vs

layout(binding=0) uniform vs_params {
    mat4 zoom;
    mat4 window_scale;
    mat4 untransform;
};

// vertex position
in vec4 position;
// in vec2 texcoord0;
// in float psize;

// struct CharElement
in vec2 tex_offset;
in vec2 tex_extent;
in vec2 size;
in vec2 offset;
// end

// struct TextElement
// TODO: some way to input the whole matrix at once?
// in vec4 transform0;
// in vec4 transform1;
// in vec4 transform2;
// in vec4 transform3;
in vec4 color0;
in float scale;
in vec3 char;
// end

out vec2 texcoord;
out vec4 color;

void main() {
    vec3 text_el = char;
    vec2 char_pos = (position.xy * size + text_el.xy + offset) * scale;
    vec4 char_pos4 = vec4(char_pos, 0.0, 1.0);
    mat4 t = untransform * window_scale * zoom;
    // float p0 = dot(transform0, position);
    // float p1 = dot(transform1, position);
    // float p2 = dot(transform2, position);
    // float p3 = dot(transform3, position);
    // gl_Position = t * vec4(p0, p1, p2, p3);
    gl_Position = t * position;
    // #ifndef SOKOL_WGSL
    // gl_PointSize = psize;
    // #endif
    vec2 texcoord0 = position.xy * vec2(1, -1);
    texcoord0 *= tex_extent;
    texcoord0 += tex_offset;
    texcoord = texcoord0;
    color = color0;
}
@end

@fs fs
layout(binding=0) uniform texture2D tex;
layout(binding=0) uniform sampler smp;
layout (binding=1) uniform fs_params {
    vec2 texture_size;
};

in vec2 texcoord;
in vec4 color;

out vec4 frag_color;

float sampleMsdf(vec2 texcoord) {
    vec3 c = texture(sampler2D(tex, smp), texcoord).rgb;
    return max(min(c.r, c.g), min(max(c.r, c.g), c.b));
}

// Antialiasing technique from Paul Houx
// https://github.com/Chlumsky/msdfgen/issues/22#issuecomment-234958005
void main() {
    // pxRange (AKA distanceRange) comes from the msdfgen tool. Don McCurdy's tool
    // uses the default which is 4.
    float pxRange = 4.0;
    vec2 sz = texture_size;
    float dx = sz.x * length(vec2(dFdx(texcoord.x), dFdy(texcoord.x)));
    float dy = sz.y * length(vec2(dFdx(texcoord.y), dFdy(texcoord.y)));
    float toPixels = pxRange * inversesqrt(dx * dx + dy * dy);
    float sigDist = sampleMsdf(texcoord) - 0.5;
    float pxDist = sigDist * toPixels;

    float edgeWidth = 0.5;
    float alpha = smoothstep(-edgeWidth, edgeWidth, pxDist);

    if (alpha < 0.001) {
        discard;
    }

    frag_color = vec4(color.rgb, color.a * alpha);
}
@end

@program text vs fs
