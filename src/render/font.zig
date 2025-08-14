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

/// High-quality vector font renderer using quadratic Bézier curves.
/// Supports Unicode text, kerning, and hinting for crisp text rendering.
///
/// Usage example:
/// ```zig
/// var font_renderer = font.Renderer.new(allocator);
/// defer font_renderer.cleanup();
///
/// // Setup with a FreeType font face
/// const setup_args = font.SetupArgs{
///     .face = my_font_face,
///     .world_size = 16.0, // Font size in pixels
///     .hinting = true,    // Enable for crisp pixel-aligned text
/// };
/// try font_renderer.setup(setup_args);
///
/// // Render text
/// font_renderer.addLine("Hello, World!", 100.0, 200.0, sg.Color{ .r = 1, .g = 1, .b = 1, .a = 1 });
/// font_renderer.updateBuffer();
///
/// // In render loop
/// font_renderer.renderInPass(vs_uniforms);
/// font_renderer.clear(); // Clear for next frame
/// ```
pub const Renderer = struct {
    bind: sg.Bindings,
    pip: sg.Pipeline,
    elements: ArrayList(Element),
    kerning_mode: ft.KerningMode,
    load_flags: ft.LoadFlags,
    em_size: f32,
    face: ft.Face,
    world_size: f32,
    hinting: bool,
    buffer_glyphs: ArrayList(BufferGlyph),
    buffer_curves: ArrayList(BufferCurve),
    glyphs: std.HashMap(u32, Glyph, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    allocator: std.mem.Allocator,
    glyph_texture: sg.Image,
    curve_texture: sg.Image,
    dilation: f32,

    pub fn new(allocator: std.mem.Allocator) Renderer {
        return .{
            .bind = .{},
            .pip = .{},
            .elements = ArrayList(Element).initCapacity(allocator, 0) catch unreachable,
            .kerning_mode = .default,
            .load_flags = .default,
            .em_size = 1.0,
            .face = undefined,
            .world_size = 1.0,
            .hinting = false,
            .buffer_glyphs = ArrayList(BufferGlyph){},
            .buffer_curves = ArrayList(BufferCurve){},
            .glyphs = std.HashMap(u32, Glyph, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
            .glyph_texture = .{},
            .curve_texture = .{},
            .dilation = 0.0,
        };
    }

    pub fn setup(self: *Renderer, args: SetupArgs) !void {
        self.face = args.face;
        self.world_size = args.world_size;
        self.hinting = args.hinting;

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

        // Build undefined glyph (index 0)
        const charcode: u32 = 0;
        const glyph_index: ft.uint = 0;
        _ = args.face.loadGlyph(glyph_index, self.load_flags) catch {
            std.log.err("[font] error while loading undefined glyph", .{});
        };
        try self.buildGlyph(charcode, glyph_index);

        // Build glyphs for ASCII printable characters
        var char: u32 = 32;
        while (char < 128) : (char += 1) {
            const glyph_idx = args.face.getCharIndex(char);
            if (glyph_idx == 0) continue;

            _ = args.face.loadGlyph(glyph_idx, self.load_flags) catch {
                std.log.err("[font] error while loading glyph for character {}", .{char});
                continue;
            };

            try self.buildGlyph(char, glyph_idx);
        }

        try self.uploadBuffers();

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

        // Setup texture buffers for glyph and curve data
        self.bind.images[shd_font.IMG_glyphs_tex] = self.glyph_texture;
        self.bind.samplers[shd_font.SMP_glyphs_smp] = sg.makeSampler(.{
            .label = "glyph sampler",
            .min_filter = .NEAREST,
            .mag_filter = .NEAREST,
            .wrap_u = .CLAMP_TO_EDGE,
            .wrap_v = .CLAMP_TO_EDGE,
        });

        self.bind.images[shd_font.IMG_curves_tex] = self.curve_texture;
        self.bind.samplers[shd_font.SMP_curves_smp] = sg.makeSampler(.{
            .label = "curve sampler",
            .min_filter = .NEAREST,
            .mag_filter = .NEAREST,
            .wrap_u = .CLAMP_TO_EDGE,
            .wrap_v = .CLAMP_TO_EDGE,
        });

        // Create pipeline
        var pip_desc: sg.PipelineDesc = .{
            .shader = sg.makeShader(shd_font.fontShaderDesc(sg.queryBackend())),
            .layout = init: {
                var l = sg.VertexLayoutState{};
                // Set instance buffer step function
                l.buffers[1].step_func = .PER_INSTANCE;

                // Vertex attribute (per-vertex)
                l.attrs[shd_font.ATTR_font_position] = .{
                    .format = .FLOAT2,
                    .buffer_index = 0,
                    .offset = 0,
                };

                // Instance attributes (per-instance)
                l.attrs[shd_font.ATTR_font_instance_position] = .{
                    .format = .FLOAT2,
                    .buffer_index = 1,
                    .offset = @offsetOf(Element, "instance_position"),
                };
                l.attrs[shd_font.ATTR_font_glyph_size] = .{
                    .format = .FLOAT2,
                    .buffer_index = 1,
                    .offset = @offsetOf(Element, "glyph_size"),
                };
                l.attrs[shd_font.ATTR_font_vertex_uv] = .{
                    .format = .FLOAT2,
                    .buffer_index = 1,
                    .offset = @offsetOf(Element, "vertex_uv"),
                };
                l.attrs[shd_font.ATTR_font_vertex_index] = .{
                    .format = .SINT32,
                    .buffer_index = 1,
                    .offset = @offsetOf(Element, "vertex_index"),
                };
                l.attrs[shd_font.ATTR_font_color] = .{
                    .format = .FLOAT4,
                    .buffer_index = 1,
                    .offset = @offsetOf(Element, "color"),
                };
                l.attrs[shd_font.ATTR_font_pixel_scale] = .{
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

    fn buildGlyph(self: *Renderer, charcode: u32, glyph_index: ft.uint) !void {
        const buffer_glyph = BufferGlyph{
            .start = @intCast(self.buffer_curves.items.len),
            .count = 0,
        };
        const buffer_glyph_index = self.buffer_glyphs.items.len;
        try self.buffer_glyphs.append(buffer_glyph);

        const glyph_slot = self.face.face.*.glyph;
        const outline = &glyph_slot.*.outline;

        // Convert contours to quadratic bezier curves
        var start: i16 = 0;
        for (0..@intCast(outline.n_contours)) |i| {
            const end = outline.contours[i];
            try self.convertContour(outline, start, end, self.em_size);
            start = end + 1;
        }

        // Update curve count
        self.buffer_glyphs.items[buffer_glyph_index].count = @intCast(self.buffer_curves.items.len - self.buffer_glyphs.items[buffer_glyph_index].start);

        // Store glyph info
        const glyph = Glyph{
            .index = glyph_index,
            .buffer_index = @intCast(buffer_glyph_index),
            .curve_count = self.buffer_glyphs.items[buffer_glyph_index].count,
            .width = glyph_slot.*.metrics.width,
            .height = glyph_slot.*.metrics.height,
            .bearing_x = glyph_slot.*.metrics.horiBearingX,
            .bearing_y = glyph_slot.*.metrics.horiBearingY,
            .advance = glyph_slot.*.metrics.horiAdvance,
        };
        try self.glyphs.put(charcode, glyph);
    }

    fn convertContour(self: *Renderer, outline: *const ft.Outline, first_index: i16, last_index: i16, em_size: f32) !void {
        if (first_index == last_index) return;

        var d_index: i16 = 1;
        var actual_first = first_index;
        var actual_last = last_index;

        if (outline.flags & ft.OUTLINE_REVERSE_FILL != 0) {
            const tmp = actual_last;
            actual_last = actual_first;
            actual_first = tmp;
            d_index = -1;
        }

        const convert = struct {
            fn call(v: ft.Vector, em: f32) [2]f32 {
                return .{
                    @as(f32, @floatFromInt(v.x)) / em,
                    @as(f32, @floatFromInt(v.y)) / em,
                };
            }
        }.call;

        const make_midpoint = struct {
            fn call(a: [2]f32, b: [2]f32) [2]f32 {
                return .{ 0.5 * (a[0] + b[0]), 0.5 * (a[1] + b[1]) };
            }
        }.call;

        const make_curve = struct {
            fn call(p0: [2]f32, p1: [2]f32, p2: [2]f32) BufferCurve {
                return BufferCurve{
                    .x0 = p0[0],
                    .y0 = p0[1],
                    .x1 = p1[0],
                    .y1 = p1[1],
                    .x2 = p2[0],
                    .y2 = p2[1],
                };
            }
        }.call;

        // Find a point that is on the curve
        var first: [2]f32 = undefined;
        const first_on_curve = (outline.tags[@intCast(actual_first)] & ft.CURVE_TAG_ON) != 0;
        if (first_on_curve) {
            first = convert(outline.points[@intCast(actual_first)], em_size);
            actual_first += d_index;
        } else {
            const last_on_curve = (outline.tags[@intCast(actual_last)] & ft.CURVE_TAG_ON) != 0;
            if (last_on_curve) {
                first = convert(outline.points[@intCast(actual_last)], em_size);
                actual_last -= d_index;
            } else {
                first = make_midpoint(convert(outline.points[@intCast(actual_first)], em_size), convert(outline.points[@intCast(actual_last)], em_size));
            }
        }

        var start = first;
        var control = first;
        var previous = first;
        var previous_tag: u8 = ft.CURVE_TAG_ON;

        var index = actual_first;
        while (index != actual_last + d_index) : (index += d_index) {
            const current = convert(outline.points[@intCast(index)], em_size);
            const current_tag = outline.tags[@intCast(index)] & ft.CURVE_TAG_MASK;

            if (current_tag == ft.CURVE_TAG_CUBIC) {
                control = previous;
            } else if (current_tag == ft.CURVE_TAG_ON) {
                if (previous_tag == ft.CURVE_TAG_CUBIC) {
                    // Cubic bezier - approximate with two quadratic curves
                    const b0 = start;
                    const b1 = control;
                    const b2 = previous;
                    const b3 = current;

                    const c0 = .{ b0[0] + 0.75 * (b1[0] - b0[0]), b0[1] + 0.75 * (b1[1] - b0[1]) };
                    const c1 = .{ b3[0] + 0.75 * (b2[0] - b3[0]), b3[1] + 0.75 * (b2[1] - b3[1]) };
                    const d = make_midpoint(c0, c1);

                    try self.buffer_curves.append(make_curve(b0, c0, d));
                    try self.buffer_curves.append(make_curve(d, c1, b3));
                } else if (previous_tag == ft.CURVE_TAG_ON) {
                    // Linear segment
                    try self.buffer_curves.append(make_curve(previous, make_midpoint(previous, current), current));
                } else {
                    // Regular bezier curve
                    try self.buffer_curves.append(make_curve(start, previous, current));
                }
                start = current;
                control = current;
            } else { // current_tag == ft.CURVE_TAG_CONIC
                if (previous_tag == ft.CURVE_TAG_ON) {
                    // Wait for third point
                } else {
                    // Create virtual on point
                    const mid = make_midpoint(previous, current);
                    try self.buffer_curves.append(make_curve(start, previous, mid));
                    start = mid;
                    control = mid;
                }
            }
            previous = current;
            previous_tag = current_tag;
        }

        // Close the contour
        if (previous_tag == ft.CURVE_TAG_CUBIC) {
            const b0 = start;
            const b1 = control;
            const b2 = previous;
            const b3 = first;

            const c0 = .{ b0[0] + 0.75 * (b1[0] - b0[0]), b0[1] + 0.75 * (b1[1] - b0[1]) };
            const c1 = .{ b3[0] + 0.75 * (b2[0] - b3[0]), b3[1] + 0.75 * (b2[1] - b3[1]) };
            const d = make_midpoint(c0, c1);

            try self.buffer_curves.append(make_curve(b0, c0, d));
            try self.buffer_curves.append(make_curve(d, c1, b3));
        } else if (previous_tag == ft.CURVE_TAG_ON) {
            // Linear segment
            try self.buffer_curves.append(make_curve(previous, make_midpoint(previous, first), first));
        } else {
            try self.buffer_curves.append(make_curve(start, previous, first));
        }
    }

    fn uploadBuffers(self: *Renderer) !void {
        // Create glyph texture (RG32I format for start/count pairs)
        var glyph_desc: sg.ImageDesc = .{
            .label = "glyph texture",
            .width = @intCast(self.buffer_glyphs.items.len),
            .height = 1,
            .pixel_format = .RG32SI,
            .sample_count = 1,
            .num_mipmaps = 1,
        };

        // Convert BufferGlyph to packed format
        const glyph_data = try self.allocator.alloc([2]i32, self.buffer_glyphs.items.len);
        defer self.allocator.free(glyph_data);
        for (self.buffer_glyphs.items, 0..) |glyph, i| {
            glyph_data[i] = .{ glyph.start, glyph.count };
        }
        glyph_desc.data.subimage[0][0] = sg.asRange(glyph_data);
        self.glyph_texture = sg.makeImage(glyph_desc);

        // Create curve texture (RG32F format, 3 points per curve)
        const curve_width = self.buffer_curves.items.len * 3;
        var curve_desc: sg.ImageDesc = .{
            .label = "curve texture",
            .width = @intCast(curve_width),
            .height = 1,
            .pixel_format = .RG32F,
            .sample_count = 1,
            .num_mipmaps = 1,
        };

        // Convert BufferCurve to packed format (3 vec2 per curve)
        const curve_data = try self.allocator.alloc([2]f32, curve_width);
        defer self.allocator.free(curve_data);
        for (self.buffer_curves.items, 0..) |curve, i| {
            curve_data[i * 3 + 0] = .{ curve.x0, curve.y0 };
            curve_data[i * 3 + 1] = .{ curve.x1, curve.y1 };
            curve_data[i * 3 + 2] = .{ curve.x2, curve.y2 };
        }
        curve_desc.data.subimage[0][0] = sg.asRange(curve_data);
        self.curve_texture = sg.makeImage(curve_desc);
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

    /// Setup shader uniforms for drawing (matches C++ drawSetup method)
    pub fn drawSetup(self: *Renderer) void {
        // Bindings are already set up in renderInPass, but this method
        // provides C++ API compatibility for advanced users who want
        // to manually control the render pipeline
        sg.applyPipeline(self.pip);
        sg.applyBindings(self.bind);
    }

    pub fn addGlyph(self: *Renderer, charcode: u32, x: f32, y: f32, color: sg.Color) void {
        const glyph = self.glyphs.get(charcode) orelse self.glyphs.get(0) orelse return;

        if (glyph.curve_count == 0) return; // Skip empty glyphs (whitespace)

        const dilation: f32 = 0.0; // Can be adjusted for anti-aliasing
        const d = self.em_size * dilation;

        const ux0 = (@as(f32, @floatFromInt(glyph.bearing_x)) - d) / self.em_size;
        const vy0 = (@as(f32, @floatFromInt(glyph.bearing_y - glyph.height)) - d) / self.em_size;
        const ux1 = (@as(f32, @floatFromInt(glyph.bearing_x + glyph.width)) + d) / self.em_size;
        const vy1 = (@as(f32, @floatFromInt(glyph.bearing_y)) + d) / self.em_size;

        const element = Element{
            .instance_position = .{ x + ux0 * self.world_size, y + vy0 * self.world_size },
            .glyph_size = .{ (ux1 - ux0) * self.world_size, (vy1 - vy0) * self.world_size },
            .vertex_uv = .{ ux0, vy0 },
            .vertex_index = glyph.buffer_index,
            .color = color,
            .pixel_scale = 1.0 / self.world_size,
        };

        self.elements.append(self.allocator, element) catch |err| {
            std.log.err("Failed to append glyph element: {}", .{err});
        };
    }

    /// Draw text and return the advance width (useful for layout calculations)
    pub fn drawAndMeasure(self: *Renderer, x: f32, y: f32, text: []const u8, color: sg.Color) f32 {
        var current_x = x;
        var previous_glyph: ft.uint = 0;

        // Decode UTF-8 text
        const utf8_view = std.unicode.Utf8View.init(text) catch |err| {
            std.log.err("Invalid UTF-8 text: {}", .{err});
            return current_x;
        };
        var iterator = utf8_view.iterator();

        while (iterator.nextCodepoint()) |codepoint| {
            if (codepoint == '\r') continue;
            if (codepoint == '\n') {
                // Handle newlines if needed
                continue;
            }

            const charcode: u32 = @intCast(codepoint);
            const glyph = self.glyphs.get(charcode) orelse self.glyphs.get(0) orelse continue;

            // Apply kerning if available
            if (previous_glyph != 0 and glyph.index != 0) {
                const kerning = self.face.getKerning(previous_glyph, glyph.index, self.kerning_mode) catch ft.Vector{ .x = 0, .y = 0 };
                current_x += @as(f32, @floatFromInt(kerning.x)) / self.em_size * self.world_size;
            }

            self.addGlyph(charcode, current_x, y, color);
            current_x += @as(f32, @floatFromInt(glyph.advance)) / self.em_size * self.world_size;
            previous_glyph = glyph.index;
        }

        return current_x;
    }

    pub const BoundingBox = struct {
        min_x: f32,
        min_y: f32,
        max_x: f32,
        max_y: f32,
    };

    pub fn measure(self: *Renderer, x: f32, y: f32, text: []const u8) BoundingBox {
        var bb = BoundingBox{
            .min_x = std.math.floatMax(f32),
            .min_y = std.math.floatMax(f32),
            .max_x = -std.math.floatMax(f32),
            .max_y = -std.math.floatMax(f32),
        };

        var current_x = x;
        var previous_glyph: ft.uint = 0;

        // Decode UTF-8 text
        const utf8_view = std.unicode.Utf8View.init(text) catch |err| {
            std.log.err("Invalid UTF-8 text: {}", .{err});
            return bb;
        };
        var iterator = utf8_view.iterator();

        while (iterator.nextCodepoint()) |codepoint| {
            if (codepoint == '\r') continue;
            if (codepoint == '\n') {
                // Handle newlines if needed
                continue;
            }

            const charcode: u32 = @intCast(codepoint);
            const glyph = self.glyphs.get(charcode) orelse self.glyphs.get(0) orelse continue;

            // Apply kerning if available
            if (previous_glyph != 0 and glyph.index != 0) {
                const kerning = self.face.getKerning(previous_glyph, glyph.index, self.kerning_mode) catch ft.Vector{ .x = 0, .y = 0 };
                current_x += @as(f32, @floatFromInt(kerning.x)) / self.em_size * self.world_size;
            }

            // Calculate glyph bounds (without dilation for exact measurement)
            const ux0 = @as(f32, @floatFromInt(glyph.bearing_x)) / self.em_size;
            const vy0 = @as(f32, @floatFromInt(glyph.bearing_y - glyph.height)) / self.em_size;
            const ux1 = @as(f32, @floatFromInt(glyph.bearing_x + glyph.width)) / self.em_size;
            const vy1 = @as(f32, @floatFromInt(glyph.bearing_y)) / self.em_size;

            const x0 = current_x + ux0 * self.world_size;
            const y0 = y + vy0 * self.world_size;
            const x1 = current_x + ux1 * self.world_size;
            const y1 = y + vy1 * self.world_size;

            if (x0 < bb.min_x) bb.min_x = x0;
            if (y0 < bb.min_y) bb.min_y = y0;
            if (x1 > bb.max_x) bb.max_x = x1;
            if (y1 > bb.max_y) bb.max_y = y1;

            current_x += @as(f32, @floatFromInt(glyph.advance)) / self.em_size * self.world_size;
            previous_glyph = glyph.index;
        }

        return bb;
    }

    pub fn prepareGlyphsForText(self: *Renderer, text: []const u8) !void {
        var changed = false;

        // Decode UTF-8 text
        const utf8_view = std.unicode.Utf8View.init(text) catch |err| {
            std.log.err("Invalid UTF-8 text: {}", .{err});
            return;
        };
        var iterator = utf8_view.iterator();

        while (iterator.nextCodepoint()) |codepoint| {
            if (codepoint == '\r' or codepoint == '\n') continue;

            const charcode: u32 = @intCast(codepoint);
            if (self.glyphs.contains(charcode)) continue;

            const glyph_index = self.face.getCharIndex(charcode);
            if (glyph_index == 0) continue;

            _ = self.face.loadGlyph(glyph_index, self.load_flags) catch {
                std.log.err("[font] error while loading glyph for character {}", .{charcode});
                continue;
            };

            try self.buildGlyph(charcode, glyph_index);
            changed = true;
        }

        if (changed) {
            try self.uploadBuffers();
        }
    }

    pub fn setWorldSize(self: *Renderer, world_size: f32) !void {
        if (world_size == self.world_size) return;
        self.world_size = world_size;

        if (!self.hinting) return;

        // Rebuild buffers for hinting
        self.em_size = world_size * 64.0;
        _ = self.face.setPixelSizes(0, @as(ft.uint, @intFromFloat(@ceil(world_size)))) catch {
            std.log.err("[font] error while setting pixel size", .{});
        };

        self.buffer_glyphs.clearRetainingCapacity();
        self.buffer_curves.clearRetainingCapacity();

        var iterator = self.glyphs.iterator();
        while (iterator.next()) |entry| {
            const charcode = entry.key_ptr.*;
            const glyph = entry.value_ptr.*;

            _ = self.face.loadGlyph(glyph.index, self.load_flags) catch {
                std.log.err("[font] error while reloading glyph for character {}", .{charcode});
                continue;
            };

            try self.buildGlyph(charcode, glyph.index);
        }

        try self.uploadBuffers();
    }

    pub fn cleanup(self: *Renderer) void {
        self.elements.deinit(self.allocator);
        self.buffer_glyphs.deinit(self.allocator);
        self.buffer_curves.deinit(self.allocator);
        self.glyphs.deinit();
    }

    /// Decodes the first Unicode code point from UTF-8 string and advances the index
    fn decodeCharcode(text: []const u8, index: *usize) u32 {
        if (index.* >= text.len) return 0;

        const first = text[index.*];

        // Fast path for ASCII
        if (first < 128) {
            index.* += 1;
            return @as(u32, first);
        }

        var result: u32 = 0;
        var size: usize = 0;

        if ((first & 0xE0) == 0xC0) { // 110xxxxx
            result = first & 0x1F;
            size = 2;
        } else if ((first & 0xF0) == 0xE0) { // 1110xxxx
            result = first & 0x0F;
            size = 3;
        } else if ((first & 0xF8) == 0xF0) { // 11110xxx
            result = first & 0x07;
            size = 4;
        } else {
            // Invalid encoding
            index.* += 1;
            return 0;
        }

        if (index.* + size > text.len) {
            index.* += 1;
            return 0;
        }

        for (1..size) |i| {
            const value = text[index.* + i];
            if ((value & 0xC0) != 0x80) { // 10xxxxxx
                index.* += 1;
                return 0;
            }
            result = (result << 6) | (value & 0x3F);
        }

        index.* += size;
        return result;
    }

    /// Add a line of text for rendering with full Unicode support and kerning.
    /// This method is similar to text.zig addLine but uses vector-based rendering
    /// for higher quality output. Supports newlines for multi-line text.
    ///
    /// Args:
    /// - text: UTF-8 encoded text string
    /// - x, y: Position in world coordinates
    /// - color: Text color
    pub fn addLine(self: *Renderer, text: []const u8, x: f32, y: f32, color: sg.Color) void {
        // Prepare all glyphs needed for this text
        self.prepareGlyphsForText(text) catch |err| {
            std.log.err("Failed to prepare glyphs for text: {}", .{err});
            return;
        };

        var current_x = x;
        const current_y = y;
        var index: usize = 0;
        var previous_glyph_index: u32 = 0;

        while (index < text.len) {
            const charcode = decodeCharcode(text, &index);
            if (charcode == 0) continue;

            const glyph = self.glyphs.get(charcode) orelse self.glyphs.get(0) orelse continue;

            // Apply kerning
            if (previous_glyph_index != 0 and glyph.index != 0) {
                const kerning = self.face.getKerning(previous_glyph_index, glyph.index, self.kerning_mode) catch ft.Vector{ .x = 0, .y = 0 };
                current_x += @as(f32, @floatFromInt(kerning.x)) / self.em_size * self.world_size;
            }

            // Add glyph quad if it has curves
            if (glyph.curve_count > 0) {
                self.addGlyph(charcode, current_x, current_y, color);
            }

            // Advance cursor
            current_x += @as(f32, @floatFromInt(glyph.advance)) / self.em_size * self.world_size;
            previous_glyph_index = glyph.index;
        }
    }

    /// Measure the bounding box of text without rendering it.
    /// Useful for layout calculations and UI positioning.
    ///
    /// Returns: BoundingBox with exact bounds of the rendered text
    pub fn measureText(self: *Renderer, text: []const u8, x: f32, y: f32) BoundingBox {
        var bbox = BoundingBox{
            .min_x = std.math.inf(f32),
            .min_y = std.math.inf(f32),
            .max_x = -std.math.inf(f32),
            .max_y = -std.math.inf(f32),
        };

        var current_x = x;
        var current_y = y;
        const original_x = x;
        var index: usize = 0;
        var previous_glyph_index: u32 = 0;

        while (index < text.len) {
            const charcode = decodeCharcode(text, &index);
            if (charcode == 0) continue;

            if (charcode == '\r') continue;

            if (charcode == '\n') {
                current_x = original_x;
                const line_height = @as(f32, @floatFromInt(self.face.height)) / @as(f32, @floatFromInt(self.face.units_per_EM)) * self.world_size;
                current_y -= line_height;
                if (self.hinting) {
                    current_y = @round(current_y);
                }
                continue;
            }

            const glyph = self.glyphs.get(charcode) orelse self.glyphs.get(0) orelse continue;

            // Apply kerning
            if (previous_glyph_index != 0 and glyph.index != 0) {
                const kerning = self.face.getKerning(previous_glyph_index, glyph.index, self.kerning_mode) catch ft.Vector{ .x = 0, .y = 0 };
                current_x += @as(f32, @floatFromInt(kerning.x)) / self.em_size * self.world_size;
            }

            // Calculate glyph bounds (without dilation for exact bounds)
            const glyph_u0 = @as(f32, @floatFromInt(glyph.bearing_x)) / self.em_size;
            const glyph_v0 = @as(f32, @floatFromInt(glyph.bearing_y - glyph.height)) / self.em_size;
            const glyph_u1 = @as(f32, @floatFromInt(glyph.bearing_x + glyph.width)) / self.em_size;
            const glyph_v1 = @as(f32, @floatFromInt(glyph.bearing_y)) / self.em_size;

            const x0 = current_x + glyph_u0 * self.world_size;
            const y0 = current_y + glyph_v0 * self.world_size;
            const x1 = current_x + glyph_u1 * self.world_size;
            const y1 = current_y + glyph_v1 * self.world_size;

            // Update bounding box
            if (x0 < bbox.min_x) bbox.min_x = x0;
            if (y0 < bbox.min_y) bbox.min_y = y0;
            if (x1 > bbox.max_x) bbox.max_x = x1;
            if (y1 > bbox.max_y) bbox.max_y = y1;

            // Advance cursor
            current_x += @as(f32, @floatFromInt(glyph.advance)) / self.em_size * self.world_size;
            previous_glyph_index = glyph.index;
        }

        return bbox;
    }

    /// Get the advance width for a space character (useful for layout)
    pub fn getSpaceAdvance(self: *Renderer) f32 {
        const space_glyph = self.glyphs.get(32) orelse return 0.0;
        return @as(f32, @floatFromInt(space_glyph.advance)) / self.em_size * self.world_size;
    }

    /// Check if a glyph is available for the given character
    pub fn hasGlyph(self: *Renderer, charcode: u32) bool {
        return self.glyphs.contains(charcode);
    }

    /// Get the line height for the current font
    pub fn getLineHeight(self: *Renderer) f32 {
        return @as(f32, @floatFromInt(self.face.height)) / @as(f32, @floatFromInt(self.face.units_per_EM)) * self.world_size;
    }
};
