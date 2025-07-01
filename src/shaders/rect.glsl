@vs vs
layout(binding=0) uniform vs_params {
    mat4 zoom;
    mat4 window_scale;
    mat4 untransform;
};

in vec2 position;
in vec4 color;
in vec2 instance_position;
in vec2 size;
in vec4 corners;
in float sigma;

out vec2 vertex;
out vec4 v_color;
out vec2 v_instance_position;
out float v_sigma;
out vec4 v_corners;
out vec2 v_size;

void main() {
    float padding = 3.0 * sigma;
    vec2 vertex_pos = mix(
        instance_position.xy - padding,
        instance_position.xy + size + padding,
        position
    );
    mat4 t = untransform * zoom * window_scale;
    gl_Position = t * vec4(vertex_pos, 0.0, 1.0);

    // Pass through values to fragment shader
    vertex = vertex_pos;
    v_color = color;
    v_instance_position = instance_position;
    v_sigma = sigma;
    v_corners = corners;
    v_size = size;
}
@end

@fs fs
const float PI = 3.141592653589793;

in vec2 vertex;
in vec4 v_color;
in vec2 v_instance_position;
in float v_sigma;
in vec4 v_corners;
in vec2 v_size;
out vec4 frag_color;

vec2 erf(vec2 x) {
    vec2 s = sign(x);
    vec2 a = abs(x);
    vec2 result = 1.0 + (0.278393 + (0.230389 + 0.078108 * (a * a)) * a) * a;
    result = result * result;
    return s - s / (result * result);
}

float gaussian(float x, float sigma) {
    return exp(-(x * x) / (2.0 * sigma * sigma)) / (sqrt(2.0 * PI) * sigma);
}

float selectCorner(float x, float y, vec4 c) {
    return mix(
        mix(c.x, c.y, step(0.0, x)),
        mix(c.w, c.z, step(0.0, x)),
        step(0.0, y)
    );
}

float roundedBoxShadowX(float x, float y, float s, float corner, vec2 halfSize) {
    float d = min(halfSize.y - corner - abs(y), 0.0);
    float c = halfSize.x - corner + sqrt(max(0.0, corner * corner - d * d));
    vec2 integral = 0.5 + 0.5 * erf((vec2(x) + vec2(-c, c)) * (sqrt(0.5) / s));
    return integral.y - integral.x;
}

float roundedBoxShadow(vec2 lower, vec2 upper, vec2 point, float sigma, vec4 corners) {
    vec2 center = (lower + upper) * 0.5;
    vec2 halfSize = (upper - lower) * 0.5;
    vec2 p = point - center;

    float low = p.y - halfSize.y;
    float high = p.y + halfSize.y;
    float start = clamp(-3.0 * sigma, low, high);
    float end = clamp(3.0 * sigma, low, high);

    float step = (end - start) / 4.0;
    float y = start + step * 0.5;
    float value = 0.0;

    for (int i = 0; i < 4; i++) {
        float corner = selectCorner(p.x, p.y, corners);
        value += roundedBoxShadowX(p.x, p.y - y, sigma, corner, halfSize) *
                gaussian(y, sigma) * step;
        y += step;
    }

    return value;
}

void main() {
    float alpha = v_color.a * roundedBoxShadow(
        v_instance_position.xy,
        v_instance_position.xy + v_size,
        vertex,
        v_sigma,
        v_corners
    );
    frag_color = vec4(v_color.rgb, alpha);
}
@end

@program rect vs fs
