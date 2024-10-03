@group(0) @binding(0) var<uniform> uni: Uniforms;

struct Uniforms {
    zoom: mat4x4<f32>,
    window_scale: mat4x4<f32>,
    untransform: mat4x4<f32>,
};

@vertex
fn vert(
    @builtin(vertex_index) vertex_index: u32
) -> @builtin(position) vec4f {
    let t = uni.untransform * uni.zoom * uni.window_scale;
    let k = uni.zoom[0][0];
    let size = exp(log(k) * 0.01) / 10.0;
    let t_pos = array(
        vec2f(-0.5, -0.5),
        vec2f(0.5, -0.5),
        vec2f(0.5, 0.5),
        vec2f(-0.5, -0.5),
        vec2f(0.5, 0.5),
        vec2f(-0.5, 0.5),
    );
    let pos = vec4f(size * t_pos[vertex_index], 0.0, 1.0) + vec4f(0.5, 0.5, 1.0, 1.0);
    return t * pos;
}

@fragment
fn frag() -> @location(0) vec4<f32> {
    let opacity = 1.0;
    // red
    return vec4<f32>(1.0, 0.0, 0.0, opacity);
}
