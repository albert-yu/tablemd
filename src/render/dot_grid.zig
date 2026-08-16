const sokol = @import("sokol");
const sg = sokol.gfx;
const shd = @import("quad_shader");
const zm = @import("zm");
const Vec2 = zm.Vec2f;
const Vec3 = zm.Vec3f;
const theme = @import("../theme.zig");
const dark_theme = theme.DARK_THEME;

pub const GRID_N = 250;
const POINTS_N = GRID_N * GRID_N;
const GRID_DENSITY: comptime_float = 1.0 / 8.0;

/// Used for layout calculations
pub const Size = struct {
    width: f32,
    height: f32,
};

pub const Renderer = struct {
    bind: sg.Bindings,
    pip: sg.Pipeline,

    grid_pos: [POINTS_N]Vec2,

    pub fn new() Renderer {
        return .{
            .bind = .{},
            .pip = .{},
            .grid_pos = undefined,
        };
    }

    /// Returns width, height of rect size of one cell
    pub fn setup(self: *Renderer) Size {
        self.bind.vertex_buffers[0] = sg.makeBuffer(.{
            .data = sg.asRange(&makeQuadVertexBuffer(dark_theme.dot_grid_color)),
        });

        // an index buffer
        self.bind.index_buffer = sg.makeBuffer(.{
            .usage = .{ .index_buffer = true },
            .data = sg.asRange(&[_]u16{
                0, 1, 2,
                0, 2, 3,
            }),
        });
        // an empty dynamic vertex buffer for the instancing data, goes in vertex buffer slot 1
        self.bind.vertex_buffers[1] = sg.makeBuffer(.{
            .usage = .{ .stream_update = true },
            .size = POINTS_N * @sizeOf(Vec3),
        });

        // a shader and pipeline state object
        var pip: sg.PipelineDesc = .{
            .shader = sg.makeShader(shd.quadShaderDesc(sg.queryBackend())),
            .layout = init: {
                var l = sg.VertexLayoutState{};
                l.buffers[1].step_func = .PER_INSTANCE;
                l.attrs[shd.ATTR_quad_position] = .{ .format = .FLOAT2, .buffer_index = 0 };
                l.attrs[shd.ATTR_quad_color0] = .{ .format = .FLOAT4, .buffer_index = 0 };
                l.attrs[shd.ATTR_quad_instance_position] = .{ .format = .FLOAT2, .buffer_index = 1 };
                break :init l;
            },
            .index_type = .UINT16,
            .depth = .{
                .compare = .LESS_EQUAL,
                .write_enabled = true,
            },
        };
        pip.colors[0].blend = .{
            .enabled = true,
            .src_factor_alpha = .SRC_ALPHA,
            .dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
            .src_factor_rgb = .SRC_ALPHA,
            .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
        };
        self.pip = sg.makePipeline(pip);
        populateXYArray(&self.grid_pos);
        sg.updateBuffer(self.bind.vertex_buffers[1], sg.asRange(self.grid_pos[0..POINTS_N]));

        const w = self.grid_pos[1][0] - self.grid_pos[0][1];
        const h = w;
        return .{
            .width = w,
            .height = h,
        };
    }

    pub fn renderInPass(self: *const Renderer, vs_range: sg.Range) void {
        sg.applyPipeline(self.pip);
        sg.applyBindings(self.bind);
        sg.applyUniforms(shd.UB_vs_params, vs_range);
        sg.draw(0, 6, POINTS_N);
    }
};

fn populateXYArray(arr: *[GRID_N * GRID_N]Vec2) void {
    var i: usize = 0;
    while (i < GRID_N * GRID_N) : (i += 1) {
        const numerX = @as(f32, @floatFromInt(i % GRID_N));
        const numerY = @as(f32, @floatFromInt(i / GRID_N));
        const denom = GRID_N * GRID_DENSITY;
        const x = numerX / denom;
        const y = numerY / denom;
        arr[i] = Vec2{ x, y };
    }
}

fn makeQuadVertexBuffer(color: sg.Color) [24]f32 {
    const v = 1.0;
    return [_]f32{
        // pos  colors
        -v, v,  color.r, color.g, color.b, color.a,
        v,  v,  color.r, color.g, color.b, color.a,
        v,  -v, color.r, color.g, color.b, color.a,
        -v, -v, color.r, color.g, color.b, color.a,
    };
}
