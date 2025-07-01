const std = @import("std");
const sokol = @import("sokol");
const RectRenderer = @import("render/rect.zig").Renderer;
const DotGridRenderer = @import("render/dot_grid.zig").Renderer;
const Transform = @import("uniforms.zig").Transform;
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
    active: bool = false,
    num_touches: u32 = 0,
    touches: [10]Vec2 = [_]Vec2{Vec2{ 0, 0 }} ** 10,
    prev_touches: [10]Vec2 = [_]Vec2{Vec2{ 0, 0 }} ** 10,
    initial_distance: f32 = 0,
    prev_distance: f32 = 0,
    center: Vec2 = Vec2{ 0, 0 },
    prev_center: Vec2 = Vec2{ 0, 0 },

    // Momentum tracking
    velocity: Vec2 = Vec2{ 0, 0 },
    last_move_time: f64 = 0,
    momentum_samples: [5]Vec2 = [_]Vec2{Vec2{ 0, 0 }} ** 5,
    momentum_times: [5]f64 = [_]f64{0} ** 5,
    momentum_index: u32 = 0,
};

const state = struct {
    var dot_grid_renderer = DotGridRenderer.new();
    var rect_renderer = RectRenderer.new();
    var pass_action: sg.PassAction = .{};
    var t = Transform.new();
    var allocator: std.mem.Allocator = undefined;

    var mouse: [2]Vec2 = .{ Vec2{ 0, 0 }, Vec2{ 0, 0 } };
    var touch_state = TouchState{};
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
                handleZoom(zoom_speed, state.mouse[0]);
            } else {
                const pan_speed = 20.0;
                handlePan(scroll_x * pan_speed, scroll_y * pan_speed);
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

    const current_time = @as(f64, @floatFromInt(std.time.milliTimestamp())) / 1000.0;

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

        // Track momentum for single touch
        const time_delta = current_time - state.touch_state.last_move_time;
        if (time_delta > 0.001) { // Avoid division by zero
            const velocity = Vec2{ dx / @as(f32, @floatCast(time_delta)), dy / @as(f32, @floatCast(time_delta)) };

            // Store velocity sample
            state.touch_state.momentum_samples[state.touch_state.momentum_index] = velocity;
            state.touch_state.momentum_times[state.touch_state.momentum_index] = current_time;
            state.touch_state.momentum_index = (state.touch_state.momentum_index + 1) % 5;
        }

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

    state.touch_state.last_move_time = current_time;
}

fn handleTouchEnded(event: *const sapp.Event) void {
    const current_time = @as(f64, @floatFromInt(std.time.milliTimestamp())) / 1000.0;

    // Compute momentum if we had a single touch and are ending all touches
    if (state.touch_state.num_touches == 1 and event.num_touches == 0) {
        const momentum = computeMomentum(current_time);
        if (momentum[0] != 0 or momentum[1] != 0) {
            applyMomentum(momentum);
        }
    }

    state.touch_state.num_touches = @intCast(event.num_touches);

    if (state.touch_state.num_touches == 0) {
        state.touch_state.active = false;
        state.touch_state.initial_distance = 0;
        state.touch_state.prev_distance = 0;
        // Reset momentum tracking
        state.touch_state.velocity = Vec2{ 0, 0 };
        state.touch_state.momentum_index = 0;
        var i: u32 = 0;
        while (i < 5) : (i += 1) {
            state.touch_state.momentum_samples[i] = Vec2{ 0, 0 };
            state.touch_state.momentum_times[i] = 0;
        }
    } else if (state.touch_state.num_touches == 1) {
        // Reset pinch state when going from multi-touch to single touch
        state.touch_state.initial_distance = 0;
        state.touch_state.prev_distance = 0;
    }
}

fn computeMomentum(current_time: f64) Vec2 {
    var total_velocity = Vec2{ 0, 0 };
    var valid_samples: u32 = 0;
    const max_age = 0.1; // Only consider samples from last 100ms

    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        const age = current_time - state.touch_state.momentum_times[i];
        if (age > 0 and age < max_age and state.touch_state.momentum_times[i] > 0) {
            // Weight newer samples more heavily
            const weight = 1.0 - @as(f32, @floatCast(age / max_age));
            total_velocity[0] += state.touch_state.momentum_samples[i][0] * weight;
            total_velocity[1] += state.touch_state.momentum_samples[i][1] * weight;
            valid_samples += 1;
        }
    }

    if (valid_samples > 0) {
        total_velocity[0] /= @as(f32, @floatFromInt(valid_samples));
        total_velocity[1] /= @as(f32, @floatFromInt(valid_samples));

        // Apply minimum threshold to avoid tiny movements
        const magnitude = @sqrt(total_velocity[0] * total_velocity[0] + total_velocity[1] * total_velocity[1]);
        if (magnitude < 50.0) { // pixels per second
            return Vec2{ 0, 0 };
        }

        return total_velocity;
    }

    return Vec2{ 0, 0 };
}

fn applyMomentum(initial_velocity: Vec2) void {
    const decay_rate = 0.95; // Velocity multiplier per frame
    const min_velocity = 1.0; // Stop when velocity is below this threshold
    const time_step = 1.0 / 60.0; // Assume 60 FPS

    var velocity = initial_velocity;
    var steps: u32 = 0;
    const max_steps = 120; // Maximum 2 seconds of momentum at 60 FPS

    while (steps < max_steps) : (steps += 1) {
        const magnitude = @sqrt(velocity[0] * velocity[0] + velocity[1] * velocity[1]);
        if (magnitude < min_velocity) break;

        // Apply momentum as pan movement
        const delta_x = velocity[0] * time_step;
        const delta_y = velocity[1] * time_step;
        handlePan(delta_x, delta_y);

        // Decay velocity
        velocity[0] *= decay_rate;
        velocity[1] *= decay_rate;
    }
}

fn handleTouchCancelled(event: *const sapp.Event) void {
    _ = event;
    state.touch_state.active = false;
    state.touch_state.num_touches = 0;
    state.touch_state.initial_distance = 0;
    state.touch_state.prev_distance = 0;
    // Reset momentum tracking
    state.touch_state.velocity = Vec2{ 0, 0 };
    state.touch_state.momentum_index = 0;
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        state.touch_state.momentum_samples[i] = Vec2{ 0, 0 };
        state.touch_state.momentum_times[i] = 0;
    }
}
