const std = @import("std");
const builtin = @import("builtin");
const sokol = @import("sokol");
const ui = @import("ui.zig");

// External JavaScript functions
extern fn set_html_render(ptr: [*]const u8, len: usize) void;
extern fn set_markdown_source(ptr: [*]const u8, len: usize) void;

const Scene = ui.Scene;
const UI = ui.UI;
const RectRenderer = @import("render/rect.zig").Renderer;
const TextRenderer = @import("render/text.zig").Renderer;
const dot_grid = @import("render/dot_grid.zig");
const DotGridRenderer = dot_grid.Renderer;
const RectDims = dot_grid.Size2D;
const Transform = @import("uniforms.zig").Transform;
const Vec2 = @import("zm").Vec2f;
const TrueType = @import("TrueType");

const io = std.io;
const sapp = sokol.app;
const slog = sokol.log;
const sg = sokol.gfx;
const sglue = sokol.glue;
const Color = sg.Color;

const CellPosition = struct {
    row: usize,
    col: usize,
};

const BG_COLOR: Color = .{ .r = 37.0 / 256.0, .g = 38.0 / 256.0, .b = 56.0 / 256.0, .a = 1 };

const WIDTH_START = 800;
const HEIGHT_START = 600;

const TouchState = struct {
    active: bool = false,
    num_touches: u32 = 0,
    touches: [10]Vec2 = [_]Vec2{Vec2{ 0, 0 }} ** 10,
    prev_touches: [10]Vec2 = [_]Vec2{Vec2{ 0, 0 }} ** 10,
    initial_distance: f32 = 0,
    prev_distance: f32 = 0,
    center: Vec2 = Vec2{ 0, 0 },
    prev_center: Vec2 = Vec2{ 0, 0 },
};

const state = struct {
    var dot_grid_renderer = DotGridRenderer.new();
    var rect_renderer = RectRenderer.new();
    var text_renderer: TextRenderer = undefined;
    var pass_action: sg.PassAction = .{};
    var t = Transform.new();
    var allocator: std.mem.Allocator = undefined;
    // This is here so that deinit can deallocate.
    // For practical purposes, we do not need to
    // deallocate on shutdown, but we can leave this
    // here to make sure we don't leak memory.
    var gpa: ?std.heap.GeneralPurposeAllocator(.{}) = null;

    var mouse: [2]Vec2 = .{ Vec2{ 0, 0 }, Vec2{ 0, 0 } };
    var touch_state = TouchState{};
    var rect_dims = RectDims{ .width = 0, .height = 0 };
    var text_dims = RectDims{ .width = 0, .height = 0 };
    var scene: Scene = undefined;
    var ui: UI = undefined;
};

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    state.allocator = if (builtin.target.cpu.arch.isWasm())
        std.heap.c_allocator
    else blk: {
        state.gpa = std.heap.GeneralPurposeAllocator(.{}){};
        break :blk state.gpa.?.allocator();
    };

    state.scene = Scene.init(state.allocator);

    state.t.updateZoom(.{ .k = 1.0, .x = 0.0, .y = 0.0 });

    // quad (dot grid binding and pipeline)
    const rect_dims = state.dot_grid_renderer.setup();
    state.rect_dims = rect_dims;
    state.rect_renderer.setup();

    // text renderer
    state.text_renderer = TextRenderer.new(state.allocator);
    const text_width = state.text_renderer.setup() catch |err| {
        std.log.err("Failed to setup text renderer: {}", .{err});
        return;
    };
    state.text_dims = RectDims{ .width = text_width, .height = rect_dims.height };
    state.ui = UI.init(state.allocator, .{
        .cell = .{ .width = rect_dims.width, .height = rect_dims.height },
        .text = .{ .width = text_width, .height = rect_dims.height },
    });

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = BG_COLOR,
    };

    state.t.updateWindowData(sapp.widthf(), sapp.heightf());
}

export fn frame() void {
    clear();
    const rect_w = state.rect_dims.width;
    const rect_h = state.rect_dims.height;
    state.ui.addSelfToScene(state.allocator, &state.scene) catch |err| {
        std.log.err("Failed to add UI to scene: {}", .{err});
    };
    state.scene.texts.append(state.allocator, .{
        .text = "hello, world! good day",
        .x = rect_w,
        .y = rect_h,
    }) catch |err| {
        std.log.err("Failed to add text: {}", .{err});
    };
    state.scene.texts.append(state.allocator, .{
        .text = "the quick brown fox jumps over the lazy dog",
        .x = 2 * rect_w,
        .y = 2 * rect_h,
    }) catch |err| {
        std.log.err("Failed to add text: {}", .{err});
    };
    for (state.scene.rects.items) |rect| {
        state.rect_renderer.add(rect);
    }
    state.rect_renderer.updateBuffer();
    for (state.scene.texts.items) |text| {
        state.text_renderer.addText(text);
    }
    state.text_renderer.updateBuffer();

    const vs_params = state.t.computeVSParams();
    const vs_range = sg.asRange(&vs_params);

    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sglue.swapchain(),
    });
    state.dot_grid_renderer.renderInPass(vs_range);
    state.rect_renderer.renderInPass(vs_range);
    state.text_renderer.renderInPass(vs_range);

    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    state.text_renderer.cleanup();
    state.scene.deinit(state.allocator);
    state.ui.deinit(state.allocator);
    sg.shutdown();

    // Clean up GPA if we created one
    if (state.gpa) |*gpa| {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.log.err("Memory leak detected!", .{});
        }
    }
}

pub fn main() void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = input,
        .width = 2 * WIDTH_START,
        .height = 2 * HEIGHT_START,
        .window_title = "tablemd",
        .logger = .{ .func = slog.func },
        // .sample_count = 4,
        .high_dpi = true,
    });
}

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

fn setHtmlRender(html: []const u8) void {
    if (builtin.target.cpu.arch.isWasm()) {
        set_html_render(html.ptr, html.len);
    } else {
        std.log.info("html:\n{s}", .{html});
    }
}

fn setMarkdownSource(markdown: []const u8) void {
    if (builtin.target.cpu.arch.isWasm()) {
        set_markdown_source(markdown.ptr, markdown.len);
    } else {
        std.log.info("markdown:\n{s}", .{markdown});
    }
}

export fn input(ev: ?*const sapp.Event) void {
    const event = ev.?;
    switch (event.type) {
        .RESIZED => {
            state.t.updateWindowData(sapp.widthf(), sapp.heightf());
        },
        .MOUSE_MOVE => {
            state.mouse[0] = Vec2{ event.mouse_x, event.mouse_y };
            const point = getPointForUI(state.mouse[0]);
            state.ui.handleMouseMove(point);
        },
        .MOUSE_SCROLL => {
            const scroll_x = event.scroll_x;
            const scroll_y = event.scroll_y;
            if ((event.modifiers & sapp.modifier_ctrl) != 0) {
                const zoom_speed = scroll_y * zoomWheelDelta(event);
                handleZoom(zoom_speed, state.mouse[0]);
            } else {
                const pan_speed = 20.0;
                handlePan(scroll_x * pan_speed, scroll_y * pan_speed);
            }
        },
        .MOUSE_DOWN => {
            const normalized_p = getPointForUI(state.mouse[0]);
            state.ui.handleMouseDown(normalized_p);
        },
        .TOUCHES_BEGAN => {
            handleTouchBegan(event);
        },
        .TOUCHES_MOVED => {
            handleTouchMoved(event);
        },
        .TOUCHES_ENDED => {
            handleTouchEnded(event);
        },
        .TOUCHES_CANCELLED => {
            handleTouchCancelled(event);
        },
        .CHAR => {
            if (isPrintableChar(event.char_code)) {
                setMarkdownSource("# Test markdown\n\nHello, world!\n\n");
                setHtmlRender("<h1>Test html</h1>");
            }
        },
        else => {},
    }
}

fn handlePan(delta_x: f32, delta_y: f32) void {
    const curr_x = state.t.getZoom().x;
    const curr_y = state.t.getZoom().y;
    const new_x = curr_x + delta_x;
    const new_y = curr_y + delta_y;
    state.t.updateZoom(.{ .k = state.t.getZoom().k, .x = new_x, .y = new_y });
}

fn handleZoom(delta: f32, p: Vec2) void {
    const curr_k = state.t.getZoom().k;
    const new_k = clamp(
        curr_k * std.math.pow(f32, 2, delta),
        0.25,
        100.0,
    );
    const inv_p = invert(p);
    const translated = translate(new_k, p, inv_p);
    state.t.updateZoom(.{ .k = new_k, .x = translated[0], .y = translated[1] });
}

/// Unapplies the zoom transform
fn invert(p: Vec2) Vec2 {
    const zoom = state.t.getZoom();
    const x = (p[0] - zoom.x) / zoom.k;
    const y = (p[1] - zoom.y) / zoom.k;
    return Vec2{ x, y };
}

fn translate(k: f32, p0: Vec2, p1: Vec2) Vec2 {
    const x = p0[0] - p1[0] * k;
    const y = p0[1] - p1[1] * k;
    return Vec2{ x, y };
}

fn zoomWheelDelta(event: *const sapp.Event) f32 {
    if ((event.modifiers & sapp.modifier_ctrl) != 0) {
        return 0.25;
    } else {
        return 0.05;
    }
}

fn clamp(x: f32, low: f32, high: f32) f32 {
    return @min(@max(x, low), high);
}

fn handleTouchBegan(event: *const sapp.Event) void {
    state.touch_state.active = true;
    state.touch_state.num_touches = @intCast(event.num_touches);

    var i: u32 = 0;
    while (i < @as(u32, @intCast(event.num_touches)) and i < 10) : (i += 1) {
        state.touch_state.touches[i] = Vec2{ event.touches[i].pos_x, event.touches[i].pos_y };
        state.touch_state.prev_touches[i] = state.touch_state.touches[i];
    }

    if (state.touch_state.num_touches >= 2) {
        // Initialize pinch gesture
        const dx = state.touch_state.touches[1][0] - state.touch_state.touches[0][0];
        const dy = state.touch_state.touches[1][1] - state.touch_state.touches[0][1];
        state.touch_state.initial_distance = @sqrt(dx * dx + dy * dy);
        state.touch_state.prev_distance = state.touch_state.initial_distance;

        // Calculate center point
        state.touch_state.center = Vec2{
            (state.touch_state.touches[0][0] + state.touch_state.touches[1][0]) * 0.5,
            (state.touch_state.touches[0][1] + state.touch_state.touches[1][1]) * 0.5,
        };
        state.touch_state.prev_center = state.touch_state.center;
    }
}

fn handleTouchMoved(event: *const sapp.Event) void {
    if (!state.touch_state.active) return;

    // Update touch positions
    var i: u32 = 0;
    while (i < @as(u32, @intCast(event.num_touches)) and i < 10) : (i += 1) {
        state.touch_state.prev_touches[i] = state.touch_state.touches[i];
        state.touch_state.touches[i] = Vec2{ event.touches[i].pos_x, event.touches[i].pos_y };
    }

    if (state.touch_state.num_touches == 1) {
        // Single touch - handle as pan/swipe
        const dx = state.touch_state.touches[0][0] - state.touch_state.prev_touches[0][0];
        const dy = state.touch_state.touches[0][1] - state.touch_state.prev_touches[0][1];
        handlePan(dx, dy);
    } else if (state.touch_state.num_touches >= 2) {
        // Multi-touch - handle as pinch and pan
        const dx = state.touch_state.touches[1][0] - state.touch_state.touches[0][0];
        const dy = state.touch_state.touches[1][1] - state.touch_state.touches[0][1];
        const current_distance = @sqrt(dx * dx + dy * dy);

        // Calculate new center
        const current_center = Vec2{
            (state.touch_state.touches[0][0] + state.touch_state.touches[1][0]) * 0.5,
            (state.touch_state.touches[0][1] + state.touch_state.touches[1][1]) * 0.5,
        };

        // Handle pinch zoom
        if (state.touch_state.prev_distance > 0) {
            const distance_ratio = current_distance / state.touch_state.prev_distance;
            if (@abs(distance_ratio - 1.0) > 0.01) { // Threshold to avoid jitter
                const zoom_delta = std.math.log2(distance_ratio);
                handleZoom(zoom_delta, current_center);
            }
        }

        // Handle pan (center movement)
        const center_dx = current_center[0] - state.touch_state.prev_center[0];
        const center_dy = current_center[1] - state.touch_state.prev_center[1];
        if (@abs(center_dx) > 1.0 or @abs(center_dy) > 1.0) { // Threshold to avoid jitter
            handlePan(center_dx, center_dy);
        }

        state.touch_state.prev_distance = current_distance;
        state.touch_state.prev_center = current_center;
    }
}

fn handleTouchEnded(event: *const sapp.Event) void {
    state.touch_state.num_touches = @intCast(event.num_touches);

    if (state.touch_state.num_touches == 0) {
        state.touch_state.active = false;
        state.touch_state.initial_distance = 0;
        state.touch_state.prev_distance = 0;
    } else if (state.touch_state.num_touches == 1) {
        // Reset pinch state when going from multi-touch to single touch
        state.touch_state.initial_distance = 0;
        state.touch_state.prev_distance = 0;
    }
}

fn handleTouchCancelled(event: *const sapp.Event) void {
    _ = event;
    state.touch_state.active = false;
    state.touch_state.num_touches = 0;
    state.touch_state.initial_distance = 0;
    state.touch_state.prev_distance = 0;
}

fn clear() void {
    state.rect_renderer.clear();
    state.text_renderer.clear();
    state.scene.clear();
}

fn normalizePt(p: Vec2) Vec2 {
    const w = sapp.widthf();
    const h = sapp.heightf();
    const min_dim = @min(w, h);
    const grid_x = p[0] / min_dim;
    const grid_y = p[1] / min_dim;
    return Vec2{ grid_x, grid_y };
}

/// Returns a normalized vec2 from a mouse position.
/// Used to feed into the UI.
fn getPointForUI(mouse_p: Vec2) Vec2 {
    const inv_p = invert(mouse_p);
    const normalized_p = normalizePt(inv_p);
    return normalized_p;
}

fn isPrintableChar(char_code: u32) bool {
    return char_code >= 32 and char_code <= 126;
}
