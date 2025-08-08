// Adpated from https://github.com/GreenLightning/gpu-font-rendering/blob/master/source/font.cpp
const std = @import("std");
const sokol = @import("sokol");
const shd_font = @import("font_shader");
const ArrayList = std.ArrayListUnmanaged;

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

pub const SetupArgs = struct {
    face: ft.Face,
    world_size: f32 = 1.0,
    hinting: bool = false,
};

pub const Renderer = struct {
    bind: sg.Bindings,
    pip: sg.Pipeline,
    elements: ArrayList(Element),
    kerning_mode: ft.KerningMode,
    load_flags: ft.LoadFlags,
    em_size: f32,

    pub fn new(allocator: std.mem.Allocator) Renderer {
        return .{
            .bind = .{},
            .pip = .{},
            .elements = ArrayList(Element).initCapacity(allocator, 0) catch unreachable,
            .kerning_mode = .default,
            .load_flags = .default,
            .em_size = 1.0,
        };
    }

    pub fn setup(self: *Renderer, args: SetupArgs) !void {
        if (args.hinting) {
            self.load_flags = .no_bitmap;
            self.kerning_mode = .default;
            self.em_size = args.world_size * 64.0;
            try args.face.setPixelSizes(0, @as(ft.uint, @intFromFloat(@ceil(args.world_size))));
        } else {
            self.load_flags = .no_scale | .no_hinting | .no_bitmap;
            self.kerning_mode = .unscaled;
            self.em_size = @as(f32, @floatFromInt(args.face.face.*.units_per_EM));
        }

        // Setup vertex buffer for quad geometry (position only)
        self.bind.vertex_buffers[0] = sg.makeBuffer(.{
            .data = sg.asRange(&[_]f32{
                0.0, 0.0, // bottom-left
                1.0, 0.0, // bottom-right
                0.0, 1.0, // top-left
                1.0, 1.0, // top-right
            }),
        });

        // Setup index buffer for quad
        self.bind.index_buffer = sg.makeBuffer(.{
            .usage = .{ .index_buffer = true },
            .data = sg.asRange(&[_]u16{
                0, 1, 2,
                1, 2, 3,
            }),
        });

        // Setup instance buffer for Element data
        self.bind.vertex_buffers[1] = sg.makeBuffer(.{
            .usage = .{ .stream_update = true },
            .size = @sizeOf(Element) * 1024, // Max instances
        });

        // TODO: Setup texture buffers for glyph and curve data
        // This will require creating 1D textures that act as texture buffers
        // to store BufferGlyph and BufferCurve data

        // Create pipeline
        var pip_desc: sg.PipelineDesc = .{
            .shader = sg.makeShader(shd_font.fontShaderDesc(sg.queryBackend())),
            .layout = init: {
                var l = sg.VertexLayoutState{};
                // Set instance buffer step function
                l.buffers[1].step_func = .PER_INSTANCE;

                // Vertex attribute (per-vertex)
                l.attrs[shd_font.ATTR_text_position] = .{
                    .format = .FLOAT2,
                    .buffer_index = 0,
                    .offset = 0,
                };

                // Instance attributes (per-instance)
                l.attrs[shd_font.ATTR_text_instance_position] = .{
                    .format = .FLOAT2,
                    .buffer_index = 1,
                    .offset = @offsetOf(Element, "instance_position"),
                };
                l.attrs[shd_font.ATTR_text_glyph_size] = .{
                    .format = .FLOAT2,
                    .buffer_index = 1,
                    .offset = @offsetOf(Element, "glyph_size"),
                };
                l.attrs[shd_font.ATTR_text_vertex_uv] = .{
                    .format = .FLOAT2,
                    .buffer_index = 1,
                    .offset = @offsetOf(Element, "vertex_uv"),
                };
                l.attrs[shd_font.ATTR_text_vertex_index] = .{
                    .format = .SINT32,
                    .buffer_index = 1,
                    .offset = @offsetOf(Element, "vertex_index"),
                };
                l.attrs[shd_font.ATTR_text_color] = .{
                    .format = .FLOAT4,
                    .buffer_index = 1,
                    .offset = @offsetOf(Element, "color"),
                };
                l.attrs[shd_font.ATTR_text_pixel_scale] = .{
                    .format = .FLOAT,
                    .buffer_index = 1,
                    .offset = @offsetOf(Element, "pixel_scale"),
                };
                break :init l;
            },
            .index_type = .UINT16,
            .depth = .{
                .compare = .LESS_EQUAL,
                .write_enabled = true,
            },
        };

        // Enable alpha blending
        pip_desc.colors[0].blend = .{
            .enabled = true,
            .src_factor_alpha = .SRC_ALPHA,
            .dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
            .src_factor_rgb = .SRC_ALPHA,
            .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
        };

        self.pip = sg.makePipeline(pip_desc);
    }

    pub fn updateBuffer(self: Renderer) void {
        if (self.elements.items.len == 0) {
            return;
        }
        sg.updateBuffer(self.bind.vertex_buffers[1], sg.asRange(self.elements.items));
    }

    pub fn clear(self: *Renderer) void {
        self.elements.clearRetainingCapacity();
    }

    pub fn renderInPass(self: Renderer, vs_range: sg.Range) void {
        sg.applyPipeline(self.pip);
        sg.applyBindings(self.bind);
        sg.applyUniforms(shd_font.UB_vs_params, vs_range);
        sg.draw(0, 6, @intCast(self.elements.items.len));
    }

    pub fn cleanup(self: *Renderer, allocator: std.mem.Allocator) void {
        self.elements.deinit(allocator);
    }
};
