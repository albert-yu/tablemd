const std = @import("std");
const parser = @import("parser.zig");
const engine = @import("engine.zig");
const sokol = @import("sokol");
const shd_quad = @import("shaders/quad.glsl.zig");
const shd_rect = @import("shaders/rect.glsl.zig");

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

const GRID_N = 1000;
const POINTS_N = GRID_N * GRID_N;
const GRID_DENSITY: comptime_float = 1.0 / 32.0;

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
    var quad = Gfx.new();
    var rect = Gfx.new();
    var pass_action: sg.PassAction = .{};

    // add matrices for transformation
    var zoom: Mat4 = Mat4.identity();
    var window_scale: Mat4 = Mat4.identity();
    var untransform: Mat4 = Mat4.identity();

    var mouse: [2]Vec2 = .{ Vec2.zero(), Vec2.zero() };

    // dot grid positions
    var grid_pos: [GRID_N * GRID_N]Vec2 = undefined;

    var rects: [RECT_N]RectElement = undefined;
    var rect_count: u32 = 0;

    pub fn updateZoom(k: f32, x: f32, y: f32) void {
        // state.zoom.m = [4][4]f32{
        //     .{ k, 0.0, 0.0, 0.0 },
        //     .{ 0.0, k, 0.0, 0.0 },
        //     .{ 0.0, 0.0, 1.0, 0.0 },
        //     .{ x, y, 0.0, 1.0 },
        // };
        state.zoom.m[0][0] = k;
        state.zoom.m[1][1] = k;
        state.zoom.m[3][0] = x;
        state.zoom.m[3][1] = y;
    }

    pub fn getZoom() Zoom {
        return .{
            .k = state.zoom.m[0][0],
            .x = state.zoom.m[3][0],
            .y = state.zoom.m[3][1],
        };
    }

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
    state.updateZoom(k, x, y);

    // quad (dot grid binding and pipeline)
    // a vertex buffer
    var quad = &state.quad;
    quad.bind.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(&makeQuadVertexBuffer(.{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 0.25 })),
    });

    // an index buffer
    quad.bind.index_buffer = sg.makeBuffer(.{
        .type = .INDEXBUFFER,
        .data = sg.asRange(&[_]u16{ 0, 1, 2, 0, 2, 3 }),
    });
    // an empty dynamic vertex buffer for the instancing data, goes in vertex buffer slot 1
    quad.bind.vertex_buffers[1] = sg.makeBuffer(.{
        .usage = .STREAM,
        .size = POINTS_N * @sizeOf(Vec3),
    });

    // a shader and pipeline state object
    var pipeline: sg.PipelineDesc = .{
        .shader = sg.makeShader(shd_quad.quadShaderDesc(sg.queryBackend())),
        .layout = init: {
            var l = sg.VertexLayoutState{};
            l.buffers[1].step_func = .PER_INSTANCE;
            l.attrs[shd_quad.ATTR_quad_position] = .{ .format = .FLOAT2, .buffer_index = 0 };
            l.attrs[shd_quad.ATTR_quad_color0] = .{ .format = .FLOAT4, .buffer_index = 0 };
            l.attrs[shd_quad.ATTR_quad_instance_position] = .{ .format = .FLOAT2, .buffer_index = 1 };
            break :init l;
        },
        .index_type = .UINT16,
        .depth = .{
            .compare = .LESS_EQUAL,
            .write_enabled = true,
        },
    };
    pipeline.colors[0].blend = .{
        .enabled = true,
        .src_factor_alpha = .SRC_ALPHA,
        .dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
        .src_factor_rgb = .SRC_ALPHA,
        .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
    };
    quad.pip = sg.makePipeline(pipeline);

    // rectangle binding and pipeline
    var rect = &state.rect;
    rect.bind.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(&[_]f32{
            0, 0,
            1, 0,
            0, 1,
            1, 0,
            0, 1,
            1, 1,
        }),
    });
    rect.bind.index_buffer = sg.makeBuffer(.{
        .type = .INDEXBUFFER,
        .data = sg.asRange(&[_]u16{
            0, 1, 2,
            3, 4, 5,
        }),
    });
    rect.bind.vertex_buffers[1] = sg.makeBuffer(.{
        .size = RECT_N * @sizeOf(RectElement),
        .usage = .STREAM,
    });
    rect.pip = sg.makePipeline(.{
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
    });

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = BG_COLOR,
    };

    populateXYArray(&state.grid_pos);
    sg.updateBuffer(quad.bind.vertex_buffers[1], sg.asRange(state.grid_pos[0..POINTS_N]));
    const rect_w = state.grid_pos[1].x - state.grid_pos[0].x;
    const rect_h = rect_w;

    state.addRect(.{
        .color = .{ 1.0, 0.0, 0.0, 1.0 },
        .position = .{ 0.0, 0.0 },
        .size = .{ rect_w, rect_h },
        .corners = .{ 0.0, 0.0, 0.0, 0.0 },
        .sigma = 1e-6,
    });
    sg.updateBuffer(rect.bind.vertex_buffers[1], sg.asRange(state.rects[0..state.rect_count]));
    updateWindowData(sapp.widthf(), sapp.heightf());
}

export fn frame() void {
    const vs_params = computeVSParams();

    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sglue.swapchain(),
    });
    sg.applyPipeline(state.quad.pip);
    sg.applyBindings(state.quad.bind);
    sg.applyUniforms(shd_quad.UB_vs_params, sg.asRange(&vs_params));
    sg.draw(0, 6, POINTS_N);
    sg.applyPipeline(state.rect.pip);
    sg.applyBindings(state.rect.bind);
    sg.applyUniforms(shd_rect.UB_vs_params, sg.asRange(&vs_params));
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

fn computeVSParams() shd_quad.VsParams {
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
            updateWindowData(sapp.widthf(), sapp.heightf());
        },
        .MOUSE_SCROLL => {
            const scroll_x = event.scroll_x;
            const scroll_y = event.scroll_y;
            if ((event.modifiers & sapp.modifier_ctrl) != 0) {
                const zoom_speed = scroll_y * zoomWheelDelta(event);
                const curr_k = state.getZoom().k;
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
                state.updateZoom(new_k, translated.x, translated.y);
            } else {
                const pan_speed = 20.0;
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

fn invert(p: Vec2) Vec2 {
    const zoom = state.getZoom();
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
    const matrices = windowTransform(scales, w, h);
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

fn windowTransform(scales: Scales, width: f32, height: f32) struct { Mat4, Mat4 } {
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

fn makeQuadVertexBuffer(color: Color) [24]f32 {
    const v = 1.0;
    return [_]f32{
        // pos  colors
        -v, v,  color.r, color.g, color.b, color.a,
        v,  v,  color.r, color.g, color.b, color.a,
        v,  -v, color.r, color.g, color.b, color.a,
        -v, -v, color.r, color.g, color.b, color.a,
    };
}
