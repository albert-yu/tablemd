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
            .x = state.zoom.m[3][0],
            .y = state.zoom.m[3][1],
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

fn computeVSParams() shd.VsParams {
    return .{
        .zoom = state.zoom,
        .window_scale = state.window_scale,
        .untransform = state.untransform,
    };
}

export fn input(ev: ?*const sapp.Event) void {
    const event = ev.?;
    switch (event.type) {
        .RESIZED => {
            const w = @as(f32, @floatFromInt(event.window_width));
            const h = @as(f32, @floatFromInt(event.window_height));
            updateWindowData(w, h);
        },
        .MOUSE_SCROLL => {
            const scroll_x = event.scroll_x;
            const scroll_y = event.scroll_y;
            if (event.modifiers & sapp.modifier_ctrl != 0) {
                const zoom_speed = 0.01;
                const curr_k = state.getZoom().k;
                const new_k = curr_k * (1.0 + scroll_y * zoom_speed);

                // update zoom
                state.updateZoom(new_k, state.getZoom().x, state.getZoom().y);
            } else {
                const pan_speed = 10.0;
                const curr_x = state.getZoom().x;
                const curr_y = state.getZoom().y;
                const new_x = curr_x + scroll_x * pan_speed;
                const new_y = curr_y + scroll_y * pan_speed;

                // update zoom
                state.updateZoom(state.getZoom().k, new_x, new_y);
            }
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
