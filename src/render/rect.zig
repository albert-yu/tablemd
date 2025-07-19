const std = @import("std");
const sokol = @import("sokol");
const shd_rect = @import("rect_shader");

const sg = sokol.gfx;

pub const RectElement = struct {
    color: [4]f32,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    corners: [4]f32,
    sigma: f32,
};

const DEFAULT_SIGMA = 1e-6;
const RECT_N = 1024;

pub const Renderer = struct {
    bind: sg.Bindings,
    pip: sg.Pipeline,
    count: u32,
    rects: [RECT_N]RectElement,

    pub fn new() Renderer {
        return .{
            .bind = .{},
            .pip = .{},
            .count = 0,
            .rects = undefined,
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
            .size = RECT_N * @sizeOf(RectElement),
            .usage = .{ .stream_update = true },
        });
        var rect_pip: sg.PipelineDesc = .{
            .shader = sg.makeShader(shd_rect.rectShaderDesc(sg.queryBackend())),
            .layout = init: {
                var l = sg.VertexLayoutState{};
                l.buffers[1].step_func = .PER_INSTANCE;
                l.attrs[shd_rect.ATTR_rect_position] = .{
                    .format = .FLOAT2,
                    .buffer_index = 0,
                };
                l.attrs[shd_rect.ATTR_rect_color] = .{
                    .format = .FLOAT4,
                    .buffer_index = 1,
                };
                l.attrs[shd_rect.ATTR_rect_instance_position] = .{
                    .format = .FLOAT2,
                    .buffer_index = 1,
                };
                l.attrs[shd_rect.ATTR_rect_size] = .{
                    .format = .FLOAT2,
                    .buffer_index = 1,
                };
                l.attrs[shd_rect.ATTR_rect_corners] = .{
                    .format = .FLOAT4,
                    .buffer_index = 1,
                };
                l.attrs[shd_rect.ATTR_rect_sigma] = .{
                    .format = .FLOAT2,
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
        rect_pip.colors[0].blend = .{
            .enabled = true,
            .src_factor_alpha = .SRC_ALPHA,
            .dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
            .src_factor_rgb = .SRC_ALPHA,
            .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
        };
        self.pip = sg.makePipeline(rect_pip);
    }

    pub fn add(self: *Renderer, rect: RectElement) void {
        if (self.count == RECT_N) {
            return;
        }
        self.rects[self.count] = rect;
        self.count += 1;
    }

    pub fn clear(self: *Renderer) void {
        self.count = 0;
    }

    /// Updates the instance buffer with the current rectangles
    pub fn updateBuffer(self: Renderer) void {
        if (self.count == 0) {
            return;
        }
        sg.updateBuffer(self.bind.vertex_buffers[1], sg.asRange(self.rects[0..self.count]));
    }

    pub fn renderInPass(self: Renderer, vs_range: sg.Range) void {
        sg.applyPipeline(self.pip);
        sg.applyBindings(self.bind);
        sg.applyUniforms(shd_rect.UB_vs_params, vs_range);
        sg.draw(0, 6, self.count);
    }
};
