const std = @import("std");
const parser = @import("parser.zig");
const engine = @import("engine.zig");
const io = std.io;
const fmt = std.fmt;
const sokol = @import("sokol");
const sapp = sokol.app;
const slog = sokol.log;
const sg = sokol.gfx;
const sglue = sokol.glue;
const shd = @import("shaders/quad.glsl.zig");

const Mat4 = @import("math.zig").Mat4;
const Vec2 = @import("math.zig").Vec2;

const print = std.debug.print;

const TICK_DURATION_NS = 16_666_667;
const MAX_FRAME_TIME_NS = 33_333_333.0; // max duration of a frame in nanoseconds
const TICK_TOLERANCE_NS = 1_000_000; // max time tolerance of a game tick in nanoseconds
const DISPLAY_PIXELS_X = 800;
const DISPLAY_PIXELS_Y = 600;

const GRID_N = 1000;
const GRID_DENSITY: comptime_float = 1.0 / 32.0;

const State = struct {
    timing: struct {
        tick: u32 = 0,
        laptime_store: u64 = 0,
        tick_accum: i32 = 0,
    } = .{},

    input: struct {
        enabled: bool = false,
        up: bool = false,
        down: bool = false,
        left: bool = false,
        right: bool = false,
        esc: bool = false,
        anykey: bool = false,
    } = .{},
    pip: sg.Pipeline = undefined,
    bind: sg.Bindings = undefined,
    pass_action: sg.PassAction = .{},

    // Add matrices for transformation
    zoom: Mat4 = Mat4.identity(),
    window_scale: Mat4 = Mat4.identity(),
    untransform: Mat4 = Mat4.identity(),

    // dot grid positions
    pos: [GRID_N * GRID_N]Vec2 = undefined,
};

var state: State = .{};

pub fn main() !void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .event_cb = input,
        .cleanup_cb = cleanup,
        .sample_count = 4,
        .width = 2 * DISPLAY_PIXELS_X,
        .height = 2 * DISPLAY_PIXELS_Y,
        .window_title = "High Performance Spreadsheet Computing",
        .logger = .{ .func = slog.func },
    });

    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer std.debug.assert(gpa.deinit() == .ok);
    // const allocator = gpa.allocator();
}

fn computeVSParams(s: State) shd.VsParams {
    return .{
        .zoom = s.zoom,
        .window_scale = s.window_scale,
        .untransform = s.untransform,
    };
}

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    // pass action to clear frame buffer to black
    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
    };
    populateXYArray(&state.pos);
}

export fn frame() void {
    const vs_params = computeVSParams(state);
    sg.beginPass(.{ .action = state.pass_action, .swapchain = sglue.swapchain() });
    sg.applyPipeline(state.pip);
    sg.applyBindings(state.bind);
    sg.applyUniforms(shd.UB_vs_params, sg.asRange(&vs_params));
    sg.draw(0, 36, 1);
    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    // TODO: cleanup
}

export fn input(ev: ?*const sapp.Event) void {
    const event = ev.?;
    if ((event.type == .KEY_DOWN) or (event.type == .KEY_UP)) {
        const key_pressed = event.type == .KEY_DOWN;
        if (state.input.enabled) {
            state.input.anykey = key_pressed;
            switch (event.key_code) {
                .W,
                .UP,
                => state.input.up = key_pressed,
                .S,
                .DOWN,
                => state.input.down = key_pressed,
                .A,
                .LEFT,
                => state.input.left = key_pressed,
                .D,
                .RIGHT,
                => state.input.right = key_pressed,
                .ESCAPE => state.input.esc = key_pressed,
                else => {},
            }
        }
    } else if ((event.type == .TOUCHES_BEGAN) or (event.type == .TOUCHES_ENDED)) {
        state.input.anykey = event.type == .TOUCHES_BEGAN;
    }
}

fn populateXYArray(arr: *[GRID_N * GRID_N]Vec2) void {
    var i: usize = 0;
    while (i < GRID_N * GRID_N) : (i += 1) {
        const numerX = @as(f32, @floatFromInt(i % GRID_N));
        const numerY = @as(f32, @floatFromInt(i / GRID_N));
        const denom = GRID_N * GRID_DENSITY;
        const x = numerX / denom;
        const y = numerY / denom;
        arr[i] = Vec2.new(x, y);
    }
}
