const std = @import("std");
const parser = @import("parser.zig");
const engine = @import("engine.zig");
const sokol = @import("sokol");
const shd = @import("shaders/quad.glsl.zig");

const io = std.io;
const fmt = std.fmt;
const sapp = sokol.app;
const slog = sokol.log;
const sg = sokol.gfx;
const sglue = sokol.glue;

const Mat4 = @import("math.zig").Mat4;
const Vec2 = @import("math.zig").Vec2;

const print = std.debug.print;

const TICK_DURATION_NS = 16_666_667;
const MAX_FRAME_TIME_NS = 33_333_333.0; // max duration of a frame in nanoseconds
const TICK_TOLERANCE_NS = 1_000_000; // max time tolerance of a game tick in nanoseconds
const DISPLAY_PIXELS_X = 800;
const DISPLAY_PIXELS_Y = 600;

const GRID_N = 100;
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
    updateWindowData(sapp.widthf(), sapp.heightf());
    sg.updateBuffer(state.bind.vertex_buffers[1], sg.asRange(state.pos[0..(GRID_N * GRID_N)]));

    // a vertex buffer
    state.bind.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(&[_]f32{
            0, 0,
            1, 0,
            0, 1,
            0, 1,
            1, 0,
            1, 1,
        }),
    });

    // an index buffer
    state.bind.index_buffer = sg.makeBuffer(.{
        .type = .INDEXBUFFER,
        .data = sg.asRange(&[_]u16{ 0, 1, 2, 4, 5 }),
    });

    // instancing data
    state.bind.vertex_buffers[1] = sg.makeBuffer(.{
        .usage = .STREAM,
        .size = GRID_N * GRID_N * @sizeOf(Vec2),
    });

    // shader and pipeline object
    // NOTE how the vertex layout is setup for instancing, with the instancing
    // data provided by buffer-slot 1:
    state.pip = sg.makePipeline(.{
        .shader = sg.makeShader(shd.quadShaderDesc(sg.queryBackend())),
        .layout = init: {
            var l = sg.VertexLayoutState{};
            l.buffers[1].step_func = .PER_INSTANCE;
            l.attrs[shd.ATTR_quad_xy] = .{ .format = .FLOAT2, .buffer_index = 0 }; // quad position
            // l.attrs[shd.ATTR_instancing_color0] = .{ .format = .FLOAT4, .buffer_index = 0 }; // colors
            // l.attrs[shd.ATTR_instancing_inst_pos] = .{ .format = .FLOAT3, .buffer_index = 1 }; // instance positions
            break :init l;
        },
        .index_type = .UINT16,
        // .cull_mode = .BACK,
        // .primitive_type = .TRIANGLES,
        // .sample_count = 4,
        .depth = .{
            .compare = .LESS_EQUAL,
            .write_enabled = false,
        },
    });
}

export fn frame() void {
    const vs_params = computeVSParams(state);

    sg.beginPass(.{ .action = state.pass_action, .swapchain = sglue.swapchain() });
    sg.applyPipeline(state.pip);
    sg.applyBindings(state.bind);
    sg.applyUniforms(shd.UB_vs_params, sg.asRange(&vs_params));
    // 6 vertices per quad
    sg.draw(0, 6, GRID_N * GRID_N);
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

fn updateWindowData(w: f32, h: f32) void {
    const range = if (w < h) w else h;
    const scales: Scales = .{
        .x = .{
            .domain = .{ .low = 0, .high = 1 },
            .range = .{ .low = 0, .high = range },
        },
        .y = .{
            .domain = .{ .low = 0, .high = 1 },
            .range = .{ .low = 0, .high = range },
        },
    };
    const matrices = window_transform(scales, w, h);
    state.zoom = matrices[0];
    state.window_scale = matrices[1];
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

const Interval = struct {
    low: f32,
    high: f32,
};

const ScaleDomainAndRange = struct {
    domain: Interval,
    range: Interval,
};

const Scales = struct {
    x: ScaleDomainAndRange,
    y: ScaleDomainAndRange,
};

fn mean(interval: Interval) f32 {
    return (interval.high - interval.low) / 2.0;
}

fn gap(interval: Interval) f32 {
    return interval.high - interval.low;
}

fn window_transform(scales: Scales, width: f32, height: f32) struct { Mat4, Mat4 } {
    const x_domain = scales.x.domain;
    const y_domain = scales.y.domain;
    const x_range = scales.x.range;
    const y_range = scales.y.range;

    const x_domain_mid = mean(x_domain);
    const y_domain_mid = mean(y_domain);
    const x_range_mid = mean(x_range);
    const y_range_mid = mean(y_range);

    const xmulti = gap(x_range) / gap(x_domain);
    const ymulti = gap(y_range) / gap(y_domain);

    // translates from data space to scaled space
    var m1 = Mat4.zero();
    m1.m = [4][4]f32{
        .{ xmulti, 0.0, 0.0, 0.0 },
        .{ 0.0, ymulti, 0.0, 0.0 },
        .{ 0.0, 0.0, 1.0, 0.0 },
        .{ -xmulti * x_domain_mid + x_range_mid, -ymulti * y_domain_mid + y_range_mid, 0.0, 1.0 },
    };

    // translate from scaled space to webgl space
    var m2 = Mat4.zero();
    m2.m = [4][4]f32{
        .{ 2.0 / width, 0.0, 0.0, 0.0 },
        .{ 0.0, -2.0 / height, 0.0, 0.0 },
        .{ 0.0, 0.0, 1.0, 0.0 },
        .{ -1.0, 1.0, 0.0, 1.0 },
    };

    return .{ m1, m2 };
}
