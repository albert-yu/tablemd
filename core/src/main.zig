const std = @import("std");
const parser = @import("parser.zig");
const engine = @import("engine.zig");
const sokol = @import("sokol");
const shd_rect = @import("shaders/rect.glsl.zig");

const dot_grid = @import("render/dot_grid.zig");
const DotGridRenderer = dot_grid.Renderer;

const uniforms = @import("uniforms.zig");
const Transform = uniforms.Transform;

const io = std.io;
const fmt = std.fmt;
const sapp = sokol.app;
const slog = sokol.log;
const sg = sokol.gfx;
const sglue = sokol.glue;

const Mat4 = @import("math.zig").Mat4;
const Vec2 = @import("math.zig").Vec2;
const Vec3 = @import("math.zig").Vec3;
const Color = sg.Color;

const print = std.debug.print;

const BG_COLOR: Color = .{ .r = 37.0 / 256.0, .g = 38.0 / 256.0, .b = 56.0 / 256.0, .a = 1 };

const RECT_N = 1000;

const WIDTH_START = 800;
const HEIGHT_START = 600;

const RectElement = struct {
    color: [4]f32,
    position: [2]f32,
    size: [2]f32,
    corners: [4]f32,
    sigma: f32,
};

const Gfx = struct {
    bind: sg.Bindings,
    pip: sg.Pipeline,

    pub fn new() Gfx {
        return .{
            .bind = .{},
            .pip = .{},
        };
    }
};

const state = struct {
    // var quad = Gfx.new();
    var dot_grid_renderer = DotGridRenderer.new();
    var rect = Gfx.new();
    var pass_action: sg.PassAction = .{};

    var t = Transform.new();

    var mouse: [2]Vec2 = .{ Vec2.zero(), Vec2.zero() };

    var rects: [RECT_N]RectElement = undefined;
    var rect_count: u32 = 0;

    pub fn addRect(element: RectElement) void {
        if (rect_count >= RECT_N) {
            return;
        }
        rects[rect_count] = element;
        rect_count += 1;
    }
};

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    const k = 1.0;
    const x = 0.0;
    const y = 0.0;
    state.t.updateZoom(.{ .k = k, .x = x, .y = y });

    // quad (dot grid binding and pipeline)
    const rect_dims = state.dot_grid_renderer.setup();

    // rectangle binding and pipeline
    var rect = &state.rect;
    rect.bind.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(&[_]f32{
            0, 0,
            1, 0,
            0, 1,
            1, 1,
        }),
    });
    rect.bind.index_buffer = sg.makeBuffer(.{
        .type = .INDEXBUFFER,
        .data = sg.asRange(&[_]u16{
            0, 1, 2,
            1, 2, 3,
        }),
    });
    rect.bind.vertex_buffers[1] = sg.makeBuffer(.{
        .size = RECT_N * @sizeOf(RectElement),
        .usage = .STREAM,
    });
    var rect_pip: sg.PipelineDesc = .{
        .shader = sg.makeShader(shd_rect.rectangleShaderDesc(sg.queryBackend())),
        .layout = init: {
            var l = sg.VertexLayoutState{};
            l.buffers[1].step_func = .PER_INSTANCE;
            l.attrs[shd_rect.ATTR_rectangle_position] = .{ .format = .FLOAT2, .buffer_index = 0 };
            l.attrs[shd_rect.ATTR_rectangle_color] = .{
                .format = .FLOAT4,
                .buffer_index = 1,
            };
            l.attrs[shd_rect.ATTR_rectangle_rect_position] = .{
                .format = .FLOAT2,
                .buffer_index = 1,
            };
            l.attrs[shd_rect.ATTR_rectangle_size] = .{
                .format = .FLOAT2,
                .buffer_index = 1,
            };
            l.attrs[shd_rect.ATTR_rectangle_corners] = .{
                .format = .FLOAT4,
                .buffer_index = 1,
            };
            l.attrs[shd_rect.ATTR_rectangle_sigma] = .{
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
    rect.pip = sg.makePipeline(rect_pip);

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = BG_COLOR,
    };

    const rect_w = rect_dims.width;
    const rect_h = rect_dims.height;

    const corner = 1.0 / 512.0;
    state.addRect(.{
        .color = .{ 1.0, 0.0, 0.0, 0.25 },
        .position = .{ 0.0, 0.0 },
        .size = .{ rect_w, rect_h },
        .corners = .{ corner, corner, corner, corner },
        .sigma = 1e-6,
    });
    sg.updateBuffer(rect.bind.vertex_buffers[1], sg.asRange(state.rects[0..state.rect_count]));
    state.t.updateWindowData(sapp.widthf(), sapp.heightf());
}

export fn frame() void {
    const vs_params = state.t.computeVSParams();
    const vs_range = sg.asRange(&vs_params);

    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sglue.swapchain(),
    });
    state.dot_grid_renderer.renderInPass(vs_range);
    sg.applyPipeline(state.rect.pip);
    sg.applyBindings(state.rect.bind);
    sg.applyUniforms(shd_rect.UB_vs_params, vs_range);
    sg.draw(0, 6, state.rect_count);

    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    sg.shutdown();
}

pub fn main() void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = input,
        .width = 2 * WIDTH_START,
        .height = 2 * HEIGHT_START,
        .icon = .{ .sokol_default = true },
        .window_title = "quad.zig",
        .logger = .{ .func = slog.func },
        // .sample_count = 4,
        .high_dpi = true,
    });
}

export fn input(ev: ?*const sapp.Event) void {
    const event = ev.?;
    switch (event.type) {
        .RESIZED => {
            state.t.updateWindowData(sapp.widthf(), sapp.heightf());
        },
        .MOUSE_SCROLL => {
            const scroll_x = event.scroll_x;
            const scroll_y = event.scroll_y;
            if ((event.modifiers & sapp.modifier_ctrl) != 0) {
                const zoom_speed = scroll_y * zoomWheelDelta(event);
                const curr_k = state.t.getZoom().k;
                const new_k = clamp(
                    curr_k * std.math.pow(f32, 2, zoom_speed),
                    0.25,
                    100.0,
                );

                const newMouse = Vec2.new(event.mouse_x, event.mouse_y);
                if (!pointsAreEqual(newMouse, state.mouse[0])) {
                    state.mouse[0] = newMouse;
                    state.mouse[1] = invert(newMouse);
                } else if (vec2IsZero(state.mouse[0]) and vec2IsZero(state.mouse[1])) {
                    state.mouse[0] = newMouse;
                    state.mouse[1] = invert(newMouse);
                }
                const translated = translate(new_k, state.mouse[0], state.mouse[1]);

                // update zoom
                state.t.updateZoom(.{ .k = new_k, .x = translated.x, .y = translated.y });
            } else {
                const pan_speed = 20.0;
                const curr_x = state.t.getZoom().x;
                const curr_y = state.t.getZoom().y;
                const new_x = curr_x + scroll_x * pan_speed;
                const new_y = curr_y + scroll_y * pan_speed;

                // update zoom
                state.t.updateZoom(.{ .k = state.t.getZoom().k, .x = new_x, .y = new_y });
            }
        },
        else => {},
    }
}

fn invert(p: Vec2) Vec2 {
    const zoom = state.t.getZoom();
    const x = (p.x - zoom.x) / zoom.k;
    const y = (p.y - zoom.y) / zoom.k;
    return Vec2.new(x, y);
}

fn translate(k: f32, p0: Vec2, p1: Vec2) Vec2 {
    const x = p0.x - p1.x * k;
    const y = p0.y - p1.y * k;
    return Vec2.new(x, y);
}

fn vec2IsZero(v: Vec2) bool {
    return v.x == 0 and v.y == 0;
}

fn floatEqual(a: f32, b: f32) bool {
    const tol = 0.0001;
    return @abs(a - b) < tol;
}

fn pointsAreEqual(p0: Vec2, p1: Vec2) bool {
    return floatEqual(p0.x, p1.x) and floatEqual(p0.y, p1.y);
}

fn zoomWheelDelta(event: *const sapp.Event) f32 {
    if ((event.modifiers & sapp.modifier_ctrl) != 0) {
        return 0.2;
    } else {
        return 0.05;
    }
}

fn clamp(x: f32, low: f32, high: f32) f32 {
    return @min(@max(x, low), high);
}
