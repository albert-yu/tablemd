@group(0) @binding(0) var<storage, read> x_values : array<f32>;
@group(0) @binding(1) var<storage, read> y_values : array<f32>;
@group(1) @binding(0) var<uniform> uni: Uniforms;

struct Uniforms {
    zoom: mat4x4<f32>,
    window_scale: mat4x4<f32>,
    untransform: mat4x4<f32>,
};

struct VertexOutput {
    @builtin(position) pos: vec4<f32>,
    @location(1) quad_position: vec2f,
};

@vertex
fn vert(@builtin(instance_index) instance_index: u32, @builtin(vertex_index) vertex_index: u32) -> VertexOutput {
    let x = x_values[instance_index];
    let y = y_values[instance_index];
    let t = uni.untransform * uni.zoom * uni.window_scale;
    let k = uni.zoom[0][0];
    let size = exp(log(k) * 0.01) / 300.0;
    let quad_pos = array(
        vec2f(0, 0),
        vec2f(1, 0),
        vec2f(0, 1),
        vec2f(0, 1),
        vec2f(1, 0),
        vec2f(1, 1),
    );
    let qp = quad_pos[vertex_index] - 0.5;
    let xy = vec4<f32>(x, y, 1.0, 1.0) + vec4f(qp * size, 0.0, 0.0);
    let pos = t * xy;
    return VertexOutput(pos, qp);
}

// Fragment
const center: vec2<f32> = vec2<f32>(0.0, 0.0);
@fragment
fn frag(input: VertexOutput) -> @location(0) vec4<f32> {
    if distance(input.quad_position, center) > 0.5 {
      discard;
    }
    let opacity = 0.25;
    return vec4<f32>(1.0, 1.0, 1.0, opacity);
}
