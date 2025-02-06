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
const Vec3 = @import("math.zig").Vec3;
const Color = sg.Color;

const print = std.debug.print;

const GRID_N = 100;
const POINTS_N = GRID_N * GRID_N;
const GRID_DENSITY: comptime_float = 1.0 / 8.0;

const BG_COLOR: Color = .{ .r = 37 / 256, .g = 38 / 256, .b = 56 / 256, .a = 1 };

const WIDTH_START = 600;
const HEIGHT_START = 600;

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

const Zoom = struct {
    k: f32,
    x: f32,
    y: f32,
};

const state = struct {
    var bind: sg.Bindings = .{};
    var pip: sg.Pipeline = .{};
    var pass_action: sg.PassAction = .{};

    // add matrices for transformation
    var zoom: Mat4 = Mat4.identity();
    var window_scale: Mat4 = Mat4.identity();
    var untransform: Mat4 = Mat4.identity();

    // dot grid positions
    var grid_pos: [GRID_N * GRID_N]Vec2 = undefined;

    fn updateZoom(k: f32, x: f32, y: f32) void {
        state.zoom.m = [4][4]f32{
            .{ k, 0.0, 0.0, 0.0 },
            .{ 0.0, k, 0.0, 0.0 },
            .{ 0.0, 0.0, 1.0, 0.0 },
            .{ x, y, 0.0, 1.0 },
        };
    }

    fn getZoom() Zoom {
        return .{
            .k = state.zoom.m[0][0],
            .x = state.zoom.m[2][0],
            .y = state.zoom.m[2][1],
        };
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
    state.updateZoom(k, x, y);

    // a vertex buffer
    const opacity = 0.25;
    const v = 1.0;
    state.bind.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(&[_]f32{
            // positions     colors
            -v, v,  v, 1.0, 1.0, 1.0, opacity,
            v,  v,  v, 1.0, 1.0, 1.0, opacity,
            v,  -v, v, 1.0, 1.0, 1.0, opacity,
            -v, -v, v, 1.0, 1.0, 1.0, opacity,
        }),
    });

    // an index buffer
    state.bind.index_buffer = sg.makeBuffer(.{
        .type = .INDEXBUFFER,
        .data = sg.asRange(&[_]u16{ 0, 1, 2, 0, 2, 3 }),
    });
    // an empty dynamic vertex buffer for the instancing data, goes in vertex buffer slot 1
    state.bind.vertex_buffers[1] = sg.makeBuffer(.{
        .usage = .STREAM,
        .size = POINTS_N * @sizeOf(Vec3),
    });

    // a shader and pipeline state object
    state.pip = sg.makePipeline(.{
        .shader = sg.makeShader(shd.quadShaderDesc(sg.queryBackend())),
        .layout = init: {
            var l = sg.VertexLayoutState{};
            l.buffers[1].step_func = .PER_INSTANCE;
            l.attrs[shd.ATTR_quad_position] = .{ .format = .FLOAT3, .buffer_index = 0 };
            l.attrs[shd.ATTR_quad_color0] = .{ .format = .FLOAT4, .buffer_index = 0 };
            l.attrs[shd.ATTR_quad_instance_position] = .{ .format = .FLOAT3, .buffer_index = 1 };
            break :init l;
        },
        .index_type = .UINT16,
        .depth = .{
            .compare = .LESS_EQUAL,
            .write_enabled = true,
        },
    });

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .store_action = .STORE,
        .clear_value = BG_COLOR,
    };

    populateXYArray(&state.grid_pos);
    sg.updateBuffer(state.bind.vertex_buffers[1], sg.asRange(state.grid_pos[0..POINTS_N]));
    updateWindowData(sapp.widthf(), sapp.heightf());
}

export fn frame() void {
    const vs_params = computeVSParams();

    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sglue.swapchain(),
    });
    sg.applyPipeline(state.pip);
    sg.applyBindings(state.bind);
    sg.applyUniforms(shd.UB_vs_params, sg.asRange(&vs_params));
    sg.draw(0, 6, POINTS_N);
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

// const TICK_DURATION_NS = 16_666_667;
// const MAX_FRAME_TIME_NS = 33_333_333.0; // max duration of a frame in nanoseconds
// const TICK_TOLERANCE_NS = 1_000_000; // max time tolerance of a game tick in nanoseconds
// const DISPLAY_PIXELS_X = 800;
// const DISPLAY_PIXELS_Y = 600;

// const State = struct {
//     timing: struct {
//         tick: u32 = 0,
//         laptime_store: u64 = 0,
//         tick_accum: i32 = 0,
//     } = .{},

//     input: struct {
//         enabled: bool = false,
//         up: bool = false,
//         down: bool = false,
//         left: bool = false,
//         right: bool = false,
//         esc: bool = false,
//         anykey: bool = false,
//     } = .{},
//     pip: sg.Pipeline = undefined,
//     bind: sg.Bindings = undefined,
//     pass_action: sg.PassAction = .{},

//     // Add matrices for transformation
//     zoom: Mat4 = Mat4.identity(),
//     window_scale: Mat4 = Mat4.identity(),
//     untransform: Mat4 = Mat4.identity(),

//     // dot grid positions
//     pos: [GRID_N * GRID_N]Vec2 = undefined,
// };

// var state: State = .{};

// pub fn main() !void {
//     sapp.run(.{
//         .init_cb = init,
//         .frame_cb = frame,
//         .event_cb = input,
//         .cleanup_cb = cleanup,
//         .sample_count = 4,
//         .width = 2 * DISPLAY_PIXELS_X,
//         .height = 2 * DISPLAY_PIXELS_Y,
//         .window_title = "High Performance Spreadsheet Computing",
//         .logger = .{ .func = slog.func },
//     });

//     // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     // defer std.debug.assert(gpa.deinit() == .ok);
//     // const allocator = gpa.allocator();
// }

fn computeVSParams() shd.VsParams {
    return .{
        .zoom = state.zoom,
        .window_scale = state.window_scale,
        .untransform = state.untransform,
    };
}

// export fn init() void {
//     sg.setup(.{
//         .environment = sglue.environment(),
//         .logger = .{ .func = slog.func },
//     });

//     // pass action to clear frame buffer to black
//     state.pass_action.colors[0] = .{
//         .load_action = .CLEAR,
//         .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
//     };
//     populateXYArray(&state.pos);
//     updateWindowData(sapp.widthf(), sapp.heightf());
//     sg.updateBuffer(state.bind.vertex_buffers[1], sg.asRange(state.pos[0..(GRID_N * GRID_N)]));

//     // a vertex buffer
//     state.bind.vertex_buffers[0] = sg.makeBuffer(.{
//         .data = sg.asRange(&[_]f32{
//             0, 0,
//             1, 0,
//             0, 1,
//             0, 1,
//             1, 0,
//             1, 1,
//         }),
//     });

//     // an index buffer
//     state.bind.index_buffer = sg.makeBuffer(.{
//         .type = .INDEXBUFFER,
//         .data = sg.asRange(&[_]u16{ 0, 1, 2, 4, 5 }),
//     });

//     // instancing data
//     state.bind.vertex_buffers[1] = sg.makeBuffer(.{
//         .usage = .STREAM,
//         .size = GRID_N * GRID_N * @sizeOf(Vec2),
//     });

//     // shader and pipeline object
//     // NOTE how the vertex layout is setup for instancing, with the instancing
//     // data provided by buffer-slot 1:
//     state.pip = sg.makePipeline(.{
//         .shader = sg.makeShader(shd.quadShaderDesc(sg.queryBackend())),
//         .layout = init: {
//             var l = sg.VertexLayoutState{};
//             l.buffers[1].step_func = .PER_INSTANCE;
//             l.attrs[shd.ATTR_quad_xy] = .{ .format = .FLOAT2, .buffer_index = 0 }; // quad position
//             // l.attrs[shd.ATTR_instancing_color0] = .{ .format = .FLOAT4, .buffer_index = 0 }; // colors
//             // l.attrs[shd.ATTR_instancing_inst_pos] = .{ .format = .FLOAT3, .buffer_index = 1 }; // instance positions
//             break :init l;
//         },
//         .index_type = .UINT16,
//         // .cull_mode = .BACK,
//         // .primitive_type = .TRIANGLES,
//         // .sample_count = 4,
//         .depth = .{
//             .compare = .LESS_EQUAL,
//             .write_enabled = false,
//         },
//     });
// }

// export fn frame() void {
//     const vs_params = computeVSParams(state);

//     sg.beginPass(.{ .action = state.pass_action, .swapchain = sglue.swapchain() });
//     sg.applyPipeline(state.pip);
//     sg.applyBindings(state.bind);
//     sg.applyUniforms(shd.UB_vs_params, sg.asRange(&vs_params));
//     // 6 vertices per quad
//     sg.draw(0, 6, GRID_N * GRID_N);
//     sg.endPass();
//     sg.commit();
// }

// export fn cleanup() void {
//     // TODO: cleanup
// }

export fn input(ev: ?*const sapp.Event) void {
    const event = ev.?;
    switch (event.type) {
        .RESIZED => {
            const w = @as(f32, @floatFromInt(event.window_width));
            const h = @as(f32, @floatFromInt(event.window_height));
            updateWindowData(w, h);
        },
        else => {},
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
    state.window_scale = matrices[0];
    state.untransform = matrices[1];
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
