const std = @import("std");
const parser = @import("parser.zig");
const engine = @import("engine.zig");
const sokol = @import("sokol");
const RectRenderer = @import("render/rect.zig").Renderer;
const DotGridRenderer = @import("render/dot_grid.zig").Renderer;
const TextRenderer = @import("render/text.zig").Renderer;
const FontRenderer = @import("render/font.zig").Renderer;
const Transform = @import("uniforms.zig").Transform;
const Vec2 = @import("math.zig").Vec2;

const io = std.io;
const fmt = std.fmt;
const sapp = sokol.app;
const slog = sokol.log;
const sg = sokol.gfx;
const sglue = sokol.glue;
const Color = sg.Color;

const print = std.debug.print;

const BG_COLOR: Color = .{ .r = 37.0 / 256.0, .g = 38.0 / 256.0, .b = 56.0 / 256.0, .a = 1 };

const WIDTH_START = 800;
const HEIGHT_START = 600;

const state = struct {
    var dot_grid_renderer = DotGridRenderer.new();
    var rect_renderer = RectRenderer.new();
    var text_renderer = TextRenderer.new();
    var pass_action: sg.PassAction = .{};
    var font_renderer: FontRenderer = undefined;
    var t = Transform.new();
    var allocator: std.mem.Allocator = undefined;

    var mouse: [2]Vec2 = .{ Vec2.zero(), Vec2.zero() };
};

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    state.allocator = gpa.allocator();

    state.font_renderer = FontRenderer.init(state.allocator, sapp.dpiScale()) catch unreachable;
    state.t.updateZoom(.{ .k = 1.0, .x = 0.0, .y = 0.0 });

    // quad (dot grid binding and pipeline)
    const rect_dims = state.dot_grid_renderer.setup();
    state.rect_renderer.setup();
    state.text_renderer.setup();

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = BG_COLOR,
    };

    const rect_w = rect_dims.width;
    const rect_h = rect_dims.height;

    const corner = 1.0 / 512.0;
    state.rect_renderer.add(.{
        .color = .{ 1.0, 0.0, 0.0, 0.25 },
        .x = 0.0,
        .y = 0.0,
        .width = rect_w,
        .height = rect_h,
        .corners = .{ corner, corner, corner, corner },
        .sigma = 1e-6,
    });
    state.rect_renderer.updateBuffer();
    state.t.updateWindowData(sapp.widthf(), sapp.heightf());
}

export fn frame() void {
    const vs_params = state.t.computeVSParams();
    const vs_range = sg.asRange(&vs_params);

    state.font_renderer.beforeRenderPass();

    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sglue.swapchain(),
    });
    state.dot_grid_renderer.renderInPass(vs_range);
    state.rect_renderer.renderInPass(vs_range);
    state.text_renderer.renderInPass(vs_range);
    state.font_renderer.renderInPass();

    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    state.font_renderer.deinit(state.allocator);
    // TODO: needed?
    state.text_renderer.cleanup();
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
