@vertex
fn main(
  @builtin(vertex_index) VertexIndex : u32
) -> @builtin(position) vec4f {
  var pos = array<vec2f, 3>(
    vec2(0.0, 1.0),
    vec2(-1.0, 0.0),
    vec2(0.0, -1.0)
  );

  return vec4f(pos[VertexIndex], 0.0, 1.0);
}
