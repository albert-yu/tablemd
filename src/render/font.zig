// Adpated from https://github.com/GreenLightning/gpu-font-rendering/blob/master/source/font.cpp
const std = @import("std");
const sokol = @import("sokol");
const shd_font = @import("font_shader");

const ft = @import("freetype");

const sg = sokol.gfx;

const Element = struct {
    instance_position: [2]f32,
    glyph_size: [2]f32,
    vertex_uv: [2]f32,
    vertex_index: i32,
    color: sg.Color,
    pixel_scale: f32,
};

const Glyph = struct {
    index: ft.uint,
    buffer_index: i32,
    curve_count: i32,
    width: ft.pos,
    height: ft.pos,
    bearing_x: ft.pos,
    bearing_y: ft.pos,
    advance: ft.pos,
};

const BufferGlyph = struct {
    start: i32,
    count: i32,
};

const BufferCurve = struct {
    x0: f32,
    y0: f32,
    x1: f32,
    y1: f32,
    x2: f32,
    y2: f32,
};

const BufferVertex = struct {
    x: f32,
    y: f32,
    u: f32,
    v: f32,
    buffer_index: i32,
};

pub const Renderer = struct {
    bind: sg.Bindings,
    pip: sg.Pipeline,

    pub fn new(allocator: std.mem.Allocator) Renderer {
        _ = allocator;
        return .{
            .bind = .{},
            .pip = .{},
        };
    }
};
