const std = @import("std");
const parser = @import("parser.zig");
const engine = @import("engine.zig");
const io = std.io;
const fmt = std.fmt;
const sokol = @import("sokol");
const sapp = sokol.app;
const slog = sokol.log;

const print = std.debug.print;

const TICK_DURATION_NS = 16_666_667;
const MAX_FRAME_TIME_NS = 33_333_333.0; // max duration of a frame in nanoseconds
const TICK_TOLERANCE_NS = 1_000_000; // max time tolerance of a game tick in nanoseconds
const DISPLAY_PIXELS_X = 800;
const DISPLAY_PIXELS_Y = 600;

export fn init() void {
    // TODO: init
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
};
var state: State = .{};

export fn frame() void {

    // run the game at a fixed tick rate regardless of frame rate
    var frame_time_ns = @as(f32, @floatCast(sapp.frameDuration() * 1000000000.0));
    // clamp max frame duration (so the timing isn't messed up when stepping in debugger)
    if (frame_time_ns > MAX_FRAME_TIME_NS) {
        frame_time_ns = MAX_FRAME_TIME_NS;
    }

    state.timing.tick_accum += @as(i32, @intFromFloat(frame_time_ns));
    while (state.timing.tick_accum > -TICK_TOLERANCE_NS) {
        state.timing.tick_accum -= TICK_DURATION_NS;
        state.timing.tick += 1;
    }
}

pub fn main() !void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .event_cb = input,
        .cleanup_cb = cleanup,
        .width = 2 * DISPLAY_PIXELS_X,
        .height = 2 * DISPLAY_PIXELS_Y,
        .window_title = "High Performance Spreadsheet Computing",
        .logger = .{ .func = slog.func },
    });

    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer std.debug.assert(gpa.deinit() == .ok);
    // const allocator = gpa.allocator();
}
