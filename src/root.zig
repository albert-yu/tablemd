const std = @import("std");
const sokol = @import("sokol");
const RectRenderer = @import("render/rect.zig").Renderer;
const DotGridRenderer = @import("render/dot_grid.zig").Renderer;
const Transform = @import("uniforms.zig").Transform;
const Zoom = @import("uniforms.zig").Zoom;
const Vec2 = @import("zm").Vec2f;

const io = std.io;
const sapp = sokol.app;
const slog = sokol.log;
const sg = sokol.gfx;
const sglue = sokol.glue;
const Color = sg.Color;

const BG_COLOR: Color = .{ .r = 37.0 / 256.0, .g = 38.0 / 256.0, .b = 56.0 / 256.0, .a = 1 };

const WIDTH_START = 800;
const HEIGHT_START = 600;

const TouchState = struct {
    id: u64,
    pos: Vec2,
    active: bool,
};

const state = struct {
    var dot_grid_renderer = DotGridRenderer.new();
    var rect_renderer = RectRenderer.new();
    var pass_action: sg.PassAction = .{};
    var t = Transform.new();
    var allocator: std.mem.Allocator = undefined;

    var mouse: [2]Vec2 = .{ Vec2{ 0, 0 }, Vec2{ 0, 0 } };

    // Touch gesture state
    var touches: [10]TouchState = [_]TouchState{TouchState{ .id = 0, .pos = Vec2{ 0, 0 }, .active = false }} ** 10;
    var touch_count: u32 = 0;
    var last_pinch_distance: f32 = 0.0;
    var last_pan_center: Vec2 = Vec2{ 0, 0 };
    var is_panning: bool = false;
    var is_pinching: bool = false;
    var gesture_start_zoom: ?Zoom = null;
    var pan_velocity: Vec2 = Vec2{ 0, 0 };
    var pan_damping: f32 = 0.85;
};

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    state.allocator = gpa.allocator();

    state.t.updateZoom(.{ .k = 1.0, .x = 0.0, .y = 0.0 });

    // quad (dot grid binding and pipeline)
    const rect_dims = state.dot_grid_renderer.setup();
    state.rect_renderer.setup();
    // state.text_renderer.setup();

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

    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sglue.swapchain(),
    });
    state.dot_grid_renderer.renderInPass(vs_range);
    state.rect_renderer.renderInPass(vs_range);
    // state.text_renderer.renderInPass(vs_range);

    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    // TODO: needed?
    // state.text_renderer.cleanup();
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
        .MOUSE_MOVE => {
            state.mouse[0] = Vec2{ event.mouse_x, event.mouse_y };
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

                state.mouse[1] = invert(state.mouse[0]);
                const translated = translate(new_k, state.mouse[0], state.mouse[1]);

                // update zoom
                state.t.updateZoom(.{ .k = new_k, .x = translated[0], .y = translated[1] });
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
        else => {},
    }
}

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
        return 0.2;
    } else {
        return 0.05;
    }
}

fn clamp(x: f32, low: f32, high: f32) f32 {
    return @min(@max(x, low), high);
}

fn handleTouchBegan(event: *const sapp.Event) void {
    // Update our touch state from sokol's touchpoints
    state.touch_count = @intCast(event.num_touches);

    for (0..@intCast(event.num_touches)) |i| {
        if (i < state.touches.len) {
            const touchpoint = event.touches[i];
            state.touches[i] = TouchState{
                .id = touchpoint.identifier,
                .pos = Vec2{ touchpoint.pos_x, touchpoint.pos_y },
                .active = true,
            };
        }
    }

    // Clear remaining slots
    for (@intCast(event.num_touches)..state.touches.len) |i| {
        state.touches[i].active = false;
    }

    updateTouchGestures();
}

fn handleTouchMoved(event: *const sapp.Event) void {
    // Update our touch state from sokol's touchpoints
    state.touch_count = @intCast(event.num_touches);

    for (0..@intCast(event.num_touches)) |i| {
        if (i < state.touches.len) {
            const touchpoint = event.touches[i];
            state.touches[i] = TouchState{
                .id = touchpoint.identifier,
                .pos = Vec2{ touchpoint.pos_x, touchpoint.pos_y },
                .active = true,
            };
        }
    }

    // Clear remaining slots
    for (@intCast(event.num_touches)..state.touches.len) |i| {
        state.touches[i].active = false;
    }

    updateTouchGestures();
}

fn handleTouchEnded(event: *const sapp.Event) void {
    // Update our touch state from sokol's touchpoints
    state.touch_count = @intCast(event.num_touches);

    for (0..@intCast(event.num_touches)) |i| {
        if (i < state.touches.len) {
            const touchpoint = event.touches[i];
            state.touches[i] = TouchState{
                .id = touchpoint.identifier,
                .pos = Vec2{ touchpoint.pos_x, touchpoint.pos_y },
                .active = true,
            };
        }
    }

    // Clear remaining slots
    for (@intCast(event.num_touches)..state.touches.len) |i| {
        state.touches[i].active = false;
    }

    if (state.touch_count == 0) {
        state.is_panning = false;
        state.is_pinching = false;
    } else {
        updateTouchGestures();
    }
}

fn handleTouchCancelled(event: *const sapp.Event) void {
    handleTouchEnded(event);
}

fn updateTouchGestures() void {
    if (state.touch_count == 1) {
        // Single touch - panning
        if (state.is_pinching) {
            // Transition from pinch to pan
            state.is_pinching = false;
            state.gesture_start_zoom = null;
        }
        handleSingleTouchPan();
    } else if (state.touch_count == 2) {
        // Two touches - pinch to zoom
        if (state.is_panning) {
            // Transition from pan to pinch
            state.is_panning = false;
            state.pan_velocity = Vec2{ 0, 0 };
        }
        handleTwoTouchPinch();
    } else {
        // No gestures
        if (state.is_panning or state.is_pinching) {
            state.is_panning = false;
            state.is_pinching = false;
            state.gesture_start_zoom = null;
            state.pan_velocity = Vec2{ 0, 0 };
        }
    }
}

fn handleSingleTouchPan() void {
    var active_touch: ?*TouchState = null;
    for (&state.touches) |*touch| {
        if (touch.active) {
            active_touch = touch;
            break;
        }
    }

    if (active_touch) |touch| {
        if (!state.is_panning) {
            state.is_panning = true;
            state.last_pan_center = touch.pos;
            state.pan_velocity = Vec2{ 0, 0 };
        } else {
            const delta = Vec2{ touch.pos[0] - state.last_pan_center[0], touch.pos[1] - state.last_pan_center[1] };

            // Update velocity for smoother movement
            state.pan_velocity[0] = state.pan_velocity[0] * state.pan_damping + delta[0] * (1.0 - state.pan_damping);
            state.pan_velocity[1] = state.pan_velocity[1] * state.pan_damping + delta[1] * (1.0 - state.pan_damping);

            const curr_x = state.t.getZoom().x;
            const curr_y = state.t.getZoom().y;
            const new_x = curr_x + state.pan_velocity[0];
            const new_y = curr_y + state.pan_velocity[1];

            state.t.updateZoom(.{ .k = state.t.getZoom().k, .x = new_x, .y = new_y });

            state.last_pan_center = touch.pos;
        }
    }
}

fn handleTwoTouchPinch() void {
    var touch1: ?*TouchState = null;
    var touch2: ?*TouchState = null;

    for (&state.touches) |*touch| {
        if (touch.active) {
            if (touch1 == null) {
                touch1 = touch;
            } else if (touch2 == null) {
                touch2 = touch;
                break;
            }
        }
    }

    if (touch1 != null and touch2 != null) {
        const t1 = touch1.?;
        const t2 = touch2.?;

        const center = Vec2{ (t1.pos[0] + t2.pos[0]) / 2.0, (t1.pos[1] + t2.pos[1]) / 2.0 };

        const dx = t2.pos[0] - t1.pos[0];
        const dy = t2.pos[1] - t1.pos[1];
        const distance = std.math.sqrt(dx * dx + dy * dy);

        if (!state.is_pinching) {
            state.is_pinching = true;
            state.last_pinch_distance = distance;
            state.last_pan_center = center;
            state.gesture_start_zoom = state.t.getZoom();
        } else {
            // Handle pinch zoom with minimum distance threshold
            if (state.last_pinch_distance > 10.0 and distance > 10.0) {
                const scale_factor = distance / state.last_pinch_distance;

                // Apply some smoothing to prevent jittery zoom
                const smoothed_scale = 1.0 + (scale_factor - 1.0) * 0.5;

                const curr_k = state.t.getZoom().k;
                const new_k = clamp(curr_k * smoothed_scale, 0.25, 100.0);

                // Zoom around the center point between the two touches
                const inverted_center = invert(center);
                const translated = translate(new_k, center, inverted_center);

                state.t.updateZoom(.{ .k = new_k, .x = translated[0], .y = translated[1] });
            }

            // Handle pan with center movement
            const center_delta = Vec2{ center[0] - state.last_pan_center[0], center[1] - state.last_pan_center[1] };

            // Apply some damping to pan movement
            const damped_delta = Vec2{ center_delta[0] * 0.8, center_delta[1] * 0.8 };

            const curr_x = state.t.getZoom().x;
            const curr_y = state.t.getZoom().y;
            const new_x = curr_x + damped_delta[0];
            const new_y = curr_y + damped_delta[1];

            state.t.updateZoom(.{ .k = state.t.getZoom().k, .x = new_x, .y = new_y });

            state.last_pinch_distance = distance;
            state.last_pan_center = center;
        }
    }
}
