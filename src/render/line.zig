const std = @import("std");
const sokol = @import("sokol");
const shd_line = @import("line_shader");

const sg = sokol.gfx;

pub const LineVertex = struct {
    x: f32,
    y: f32,
    color: sg.Color,
};

pub const LineElement = struct {
    p0: [2]f32,
    p1: [2]f32,
    color: sg.Color,
};

const MAX_LINES = 8192;
const MAX_VERTICES = MAX_LINES * 2;

pub const Renderer = struct {
    bind: sg.Bindings,
    pip: sg.Pipeline,
    count: u32,
    vertices: [MAX_VERTICES]LineVertex,

    pub fn new() Renderer {
        return .{
            .bind = .{},
            .pip = .{},
            .count = 0,
            .vertices = undefined,
        };
    }

    pub fn setup(self: *Renderer) void {
        self.bind.vertex_buffers[0] = sg.makeBuffer(.{
            .size = MAX_VERTICES * @sizeOf(LineVertex),
            .usage = .{ .stream_update = true },
        });

        var line_pip: sg.PipelineDesc = .{
            .shader = sg.makeShader(shd_line.lineShaderDesc(sg.queryBackend())),
            .primitive_type = .LINES,
            .layout = init: {
                var l = sg.VertexLayoutState{};
                l.attrs[shd_line.ATTR_line_position] = .{
                    .format = .FLOAT2,
                    .buffer_index = 0,
                };
                l.attrs[shd_line.ATTR_line_color] = .{
                    .format = .FLOAT4,
                    .buffer_index = 0,
                };
                break :init l;
            },
            .depth = .{
                .compare = .LESS_EQUAL,
                .write_enabled = true,
            },
        };
        line_pip.colors[0].blend = .{
            .enabled = true,
            .src_factor_alpha = .SRC_ALPHA,
            .dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
            .src_factor_rgb = .SRC_ALPHA,
            .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
        };
        self.pip = sg.makePipeline(line_pip);
    }

    pub fn add(self: *Renderer, line: LineElement) void {
        if (self.count + 2 > MAX_VERTICES) {
            return;
        }
        self.vertices[self.count] = .{
            .x = line.p0[0],
            .y = line.p0[1],
            .color = line.color,
        };
        self.vertices[self.count + 1] = .{
            .x = line.p1[0],
            .y = line.p1[1],
            .color = line.color,
        };
        self.count += 2;
    }

    pub fn clear(self: *Renderer) void {
        self.count = 0;
    }

    /// Updates the vertex buffer with the current vertices
    pub fn updateBuffer(self: *Renderer) void {
        if (self.count == 0) {
            return;
        }
        sg.updateBuffer(self.bind.vertex_buffers[0], sg.asRange(self.vertices[0..self.count]));
    }

    pub fn renderInPass(self: *const Renderer, vs_range: sg.Range) void {
        if (self.count == 0) {
            return;
        }
        sg.applyPipeline(self.pip);
        sg.applyBindings(self.bind);
        sg.applyUniforms(shd_line.UB_vs_params, vs_range);
        sg.draw(0, self.count, 1);
    }
};
