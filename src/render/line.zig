const std = @import("std");
const sokol = @import("sokol");
const shd_line = @import("line_shader");

const sg = sokol.gfx;

pub const DEFAULT_LINE_WIDTH: f32 = 1.0 / 800.0;

pub const LineElement = struct {
    p0: [2]f32,
    p1: [2]f32,
    color: sg.Color,
    width: f32 = DEFAULT_LINE_WIDTH,
};

const MAX_LINES = 8192;

pub const Renderer = struct {
    bind: sg.Bindings,
    pip: sg.Pipeline,
    count: u32,
    lines: [MAX_LINES]LineElement,

    pub fn new() Renderer {
        return .{
            .bind = .{},
            .pip = .{},
            .count = 0,
            .lines = undefined,
        };
    }

    pub fn setup(self: *Renderer) void {
        self.bind.vertex_buffers[0] = sg.makeBuffer(.{
            .data = sg.asRange(&[_]f32{
                0, 0,
                1, 0,
                0, 1,
                1, 1,
            }),
        });
        self.bind.index_buffer = sg.makeBuffer(.{
            .usage = .{ .index_buffer = true },
            .data = sg.asRange(&[_]u16{
                0, 1, 2,
                1, 2, 3,
            }),
        });
        self.bind.vertex_buffers[1] = sg.makeBuffer(.{
            .size = MAX_LINES * @sizeOf(LineElement),
            .usage = .{ .stream_update = true },
        });

        var line_pip: sg.PipelineDesc = .{
            .shader = sg.makeShader(shd_line.lineShaderDesc(sg.queryBackend())),
            .layout = init: {
                var l = sg.VertexLayoutState{};
                l.buffers[1].step_func = .PER_INSTANCE;
                l.attrs[shd_line.ATTR_line_position] = .{
                    .format = .FLOAT2,
                    .buffer_index = 0,
                };
                l.attrs[shd_line.ATTR_line_p0] = .{
                    .format = .FLOAT2,
                    .buffer_index = 1,
                };
                l.attrs[shd_line.ATTR_line_p1] = .{
                    .format = .FLOAT2,
                    .buffer_index = 1,
                };
                l.attrs[shd_line.ATTR_line_color] = .{
                    .format = .FLOAT4,
                    .buffer_index = 1,
                };
                l.attrs[shd_line.ATTR_line_width] = .{
                    .format = .FLOAT,
                    .buffer_index = 1,
                };
                break :init l;
            },
            .index_type = .UINT16,
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
        if (self.count == MAX_LINES) {
            return;
        }
        self.lines[self.count] = line;
        self.count += 1;
    }

    pub fn clear(self: *Renderer) void {
        self.count = 0;
    }

    /// Updates the instance buffer with the current lines
    pub fn updateBuffer(self: *Renderer) void {
        if (self.count == 0) {
            return;
        }
        sg.updateBuffer(self.bind.vertex_buffers[1], sg.asRange(self.lines[0..self.count]));
    }

    pub fn renderInPass(self: *const Renderer, vs_range: sg.Range) void {
        if (self.count == 0) {
            return;
        }
        sg.applyPipeline(self.pip);
        sg.applyBindings(self.bind);
        sg.applyUniforms(shd_line.UB_vs_params, vs_range);
        sg.draw(0, 6, self.count);
    }
};
