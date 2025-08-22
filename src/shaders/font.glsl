@vs vs
layout(binding = 0) uniform vs_params {
    mat4 zoom;
    mat4 window_scale;
    mat4 untransform;
};



layout (location = 0) in vec2 position;
layout (location = 1) in vec2 vertex_uv;
layout (location = 2) in int  vertex_index;

layout (location = 0) out vec2 uv;
layout (location = 1) flat out int buffer_index;

void main() {
    mat4 t = untransform * zoom * window_scale;
    // vec2 scaled_pos = (position * glyph_size + instance_position) * pixel_scale;
    gl_Position = t * vec4(position, 0.0, 1.0);
    // v_color = color;
    uv = vertex_uv;
    buffer_index = vertex_index;
}
@end

@fs fs

// Based on: http://wdobbie.com/post/gpu-text-rendering-with-vector-textures/

struct Glyph {
    int start, count;
};

struct Curve {
    vec2 p0, p1, p2;
};

layout(binding=0) uniform texture2D glyphs_tex;
layout(binding=0) uniform sampler glyphs_smp;
layout(binding=1) uniform texture2D curves_tex;
layout(binding=1) uniform sampler curves_smp;


in vec2 uv;
flat in int buffer_index;
// in vec4 v_color;

out vec4 result;

Glyph loadGlyph(int index) {
    Glyph result;
    vec2 texCoord = vec2(float(index) + 0.5, 0.5) / textureSize(sampler2D(glyphs_tex, glyphs_smp), 0);
    vec2 data = texture(sampler2D(glyphs_tex, glyphs_smp), texCoord).xy;
    result.start = int(data.x);
    result.count = int(data.y);
    return result;
}

Curve loadCurve(int index) {
    Curve result;
    vec2 texSize = textureSize(sampler2D(curves_tex, curves_smp), 0);

    vec2 texCoord0 = vec2(float(3 * index + 0) + 0.5, 0.5) / texSize;
    vec2 texCoord1 = vec2(float(3 * index + 1) + 0.5, 0.5) / texSize;
    vec2 texCoord2 = vec2(float(3 * index + 2) + 0.5, 0.5) / texSize;

    result.p0 = texture(sampler2D(curves_tex, curves_smp), texCoord0).xy;
    result.p1 = texture(sampler2D(curves_tex, curves_smp), texCoord1).xy;
    result.p2 = texture(sampler2D(curves_tex, curves_smp), texCoord2).xy;
    return result;
}

float computeCoverage(float inverseDiameter, vec2 p0, vec2 p1, vec2 p2) {
    if (p0.y > 0 && p1.y > 0 && p2.y > 0) return 0.0;
    if (p0.y < 0 && p1.y < 0 && p2.y < 0) return 0.0;

    // Note: Simplified from abc formula by extracting a factor of (-2) from b.
    vec2 a = p0 - 2 * p1 + p2;
    vec2 b = p0 - p1;
    vec2 c = p0;

    float t0, t1;
    if (abs(a.y) >= 1e-5) {
        // Quadratic segment, solve abc formula to find roots.
        float radicand = b.y * b.y - a.y * c.y;
        if (radicand <= 0) return 0.0;

        float s = sqrt(radicand);
        t0 = (b.y - s) / a.y;
        t1 = (b.y + s) / a.y;
    } else {
        // Linear segment, avoid division by a.y, which is near zero.
        // There is only one root, so we have to decide which variable to
        // assign it to based on the direction of the segment, to ensure that
        // the ray always exits the shape at t0 and enters at t1. For a
        // quadratic segment this works 'automatically', see readme.
        float t = p0.y / (p0.y - p2.y);
        if (p0.y < p2.y) {
            t0 = -1.0;
            t1 = t;
        } else {
            t0 = t;
            t1 = -1.0;
        }
    }

    float alpha = 0;

    if (t0 >= 0 && t0 < 1) {
        float x = (a.x * t0 - 2.0 * b.x) * t0 + c.x;
        alpha += clamp(x * inverseDiameter + 0.5, 0, 1);
    }

    if (t1 >= 0 && t1 < 1) {
        float x = (a.x * t1 - 2.0 * b.x) * t1 + c.x;
        alpha -= clamp(x * inverseDiameter + 0.5, 0, 1);
    }

    return alpha;
}

vec2 rotate(vec2 v) {
    return vec2(v.y, -v.x);
}

void main() {
    // Controls for debugging and exploring:

    // Size of the window (in pixels) used for 1-dimensional anti-aliasing along each rays.
    //   0 - no anti-aliasing
    //   1 - normal anti-aliasing
    // >=2 - exaggerated effect
    float antiAliasingWindowSize = 1.0;

    // Enable a second ray along the y-axis to achieve 2-dimensional anti-aliasing.
    bool enableSuperSamplingAntiAliasing = true;

    // Draw control points for debugging (green - on curve, magenta - off curve).
    bool enableControlPointsVisualization = false;

    float alpha = 0;

    // Inverse of the diameter of a pixel in uv units for anti-aliasing.
    vec2 inverseDiameter = 1.0 / (antiAliasingWindowSize * fwidth(uv));

    Glyph glyph = loadGlyph(buffer_index);
    for (int i = 0; i < glyph.count; i++) {
        Curve curve = loadCurve(glyph.start + i);

        vec2 p0 = curve.p0 - uv;
        vec2 p1 = curve.p1 - uv;
        vec2 p2 = curve.p2 - uv;

        alpha += computeCoverage(inverseDiameter.x, p0, p1, p2);
        if (enableSuperSamplingAntiAliasing) {
            alpha += computeCoverage(inverseDiameter.y, rotate(p0), rotate(p1), rotate(p2));
        }
    }

    if (enableSuperSamplingAntiAliasing) {
        alpha *= 0.5;
    }


    alpha = clamp(alpha, 0.0, 1.0);
    vec4 v_color = vec4(1.0, 1.0, 1.0, alpha);
    result = v_color * alpha;

    if (enableControlPointsVisualization) {
        // Visualize control points.
        vec2 fw = fwidth(uv);
        float r = 4.0 * 0.5 * (fw.x + fw.y);
        for (int i = 0; i < glyph.count; i++) {
            Curve curve = loadCurve(glyph.start + i);

            vec2 p0 = curve.p0 - uv;
            vec2 p1 = curve.p1 - uv;
            vec2 p2 = curve.p2 - uv;

            if (dot(p0, p0) < r * r || dot(p2, p2) < r * r) {
                result = vec4(0, 1, 0, 1);
                return;
            }

            if (dot(p1, p1) < r * r) {
                result = vec4(1, 0, 1, 1);
                return;
            }
        }
    }
}
@end

@program font vs fs
