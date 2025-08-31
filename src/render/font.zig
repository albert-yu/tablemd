// Adpated from https://github.com/GreenLightning/gpu-font-rendering/blob/master/source/font.cpp
const std = @import("std");
const sokol = @import("sokol");
const shd_font = @import("font_shader");
const ArrayList = std.ArrayListUnmanaged;

const ft = @import("freetype");

const sg = sokol.gfx;

pub const BoundingBox = struct {
    min_x: f32,
    min_y: f32,
    max_x: f32,
    max_y: f32,
};

pub const TextElement = struct {
    text: []const u8,
    x: f32,
    y: f32,
};

const Glyph = struct {
    index: ft.UInt,
    buffer_index: i32,
    curve_count: i32,
    width: ft.Pos,
    height: ft.Pos,
    bearing_x: ft.Pos,
    bearing_y: ft.Pos,
    advance: ft.Pos,
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

const WHITE = sg.Color{ .r = 1, .g = 1, .b = 1, .a = 1 };

pub const SetupArgs = struct {
    world_size: f32 = 0.025,
    /// WARNING: do not use this for now, it's broken
    hinting: bool = false,
    color: sg.Color = WHITE,
};

const MAX_ELEMENTS = 2048;
const MAX_INDICES = MAX_ELEMENTS * 6 / 4;

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
///     .world_size = 16.0, // Font size in pixels
///     .hinting = false,
///     .color = .{ .r = 1, .g = 1, .b = 1, .a = 1 },
/// };
/// try font_renderer.setup(setup_args);
///
/// // Render text
/// font_renderer.addLine("Hello, World!", x, y);
/// font_renderer.updateBuffer();
///
/// // In render loop
/// font_renderer.renderInPass(vs_uniforms);
/// font_renderer.clear(); // Clear for next frame
/// ```
pub const Renderer = struct {
    bind: sg.Bindings,
    pip: sg.Pipeline,
    kerning_mode: ft.KerningMode,
    load_flags: ft.LoadFlags,
    em_size: f32,
    font: ft.Font,
    world_size: f32,
    hinting: bool,
    buffer_glyphs: ArrayList(BufferGlyph),
    buffer_curves: ArrayList(BufferCurve),
    glyphs: std.HashMap(u32, Glyph, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    allocator: std.mem.Allocator,
    glyph_texture: sg.Image,
    curve_texture: sg.Image,
    dilation: f32,
    text_elements: ArrayList(TextElement),
    color: sg.Color,

    pub fn new(allocator: std.mem.Allocator) Renderer {
        return .{
            .bind = .{},
            .pip = .{},
            .kerning_mode = .default,
            .load_flags = ft.LOAD_DEFAULT,
            .em_size = 1.0,
            .font = undefined,
            .world_size = 1.0,
            .hinting = false,
            .buffer_glyphs = ArrayList(BufferGlyph).initCapacity(allocator, 0) catch unreachable,
            .buffer_curves = ArrayList(BufferCurve).initCapacity(allocator, 0) catch unreachable,
            .glyphs = std.HashMap(u32, Glyph, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
            .glyph_texture = .{},
            .curve_texture = .{},
            .dilation = 0.1,
            .text_elements = ArrayList(TextElement).initCapacity(allocator, 0) catch unreachable,
            .color = WHITE,
        };
    }

    pub fn setup(self: *Renderer, args: SetupArgs) !f32 {
        const font_data = @embedFile("../fonts/SpaceMono-Regular.ttf");
        const font = try ft.load(font_data);
        self.font = font;
        self.world_size = args.world_size;
        self.hinting = args.hinting;
        self.color = args.color;
        var face = self.font.face;

        if (args.hinting) {
            self.load_flags = ft.LOAD_NO_BITMAP;
            self.kerning_mode = .default;
            self.em_size = args.world_size * 64.0;
            try face.setPixelSizes(0, @as(ft.UInt, @intFromFloat(@ceil(args.world_size))));
        } else {
            self.load_flags = ft.LOAD_NO_SCALE | ft.LOAD_NO_HINTING | ft.LOAD_NO_BITMAP;
            self.kerning_mode = .unscaled;
            self.em_size = @as(f32, @floatFromInt(face.face.*.units_per_EM));
        }

        // Build undefined glyph (index 0)
        {
            const charcode: u32 = 0;
            const glyph_index: ft.UInt = 0;
            _ = face.loadGlyph(glyph_index, self.load_flags) catch {
                std.log.err("[font] error while loading undefined glyph", .{});
                // Continue, because we always want an entry for the undefined glyph in our glyphs map!
            };
            try self.buildGlyph(charcode, glyph_index);
        }

        // Build glyphs for ASCII printable characters
        var char: u32 = 32;
        while (char < 128) : (char += 1) {
            const glyph_idx = face.getGlyphIndex(char);
            if (glyph_idx == 0) continue;

            _ = self.font.face.loadGlyph(glyph_idx, self.load_flags) catch {
                std.log.err("[font] error while loading glyph for character {}", .{char});
                continue;
            };

            try self.buildGlyph(char, glyph_idx);
        }

        try self.uploadGlyphsAndCurvesToTextures();

        self.bind.vertex_buffers[0] = sg.makeBuffer(.{
            .usage = .{ .stream_update = true },
            .size = @sizeOf(BufferVertex) * MAX_ELEMENTS,
        });

        self.bind.index_buffer = sg.makeBuffer(.{
            .usage = .{ .index_buffer = true, .stream_update = true },
            .size = @sizeOf(i32) * MAX_INDICES,
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

                // Vertex attribute (per-vertex)
                l.attrs[shd_font.ATTR_font_position] = .{
                    .format = .FLOAT2,
                    .buffer_index = 0,
                    .offset = 0,
                };
                l.attrs[shd_font.ATTR_font_vertex_uv] = .{
                    .format = .FLOAT2,
                    .buffer_index = 0,
                };
                l.attrs[shd_font.ATTR_font_vertex_index] = .{
                    .format = .INT,
                    .buffer_index = 0,
                };
                break :init l;
            },
            .index_type = .UINT32,
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
        return self.getSpaceAdvance();
    }

    fn buildGlyph(self: *Renderer, charcode: u32, glyph_index: ft.UInt) !void {
        var buffer_glyph = BufferGlyph{
            .start = @intCast(self.buffer_curves.items.len),
            .count = 0,
        };

        const glyph_slot = self.font.face.face.*.glyph;
        const outline = &glyph_slot.*.outline;

        // Convert contours to quadratic bezier curves
        var start: i16 = 0;
        for (0..@intCast(outline.n_contours)) |i| {
            const end = outline.contours[i];
            try self.convertContour(outline, start, end, self.em_size);
            start = end + 1;
        }

        // Update curve count
        buffer_glyph.count = @intCast(self.buffer_curves.items.len - @as(usize, @intCast(buffer_glyph.start)));

        const buffer_index = self.buffer_glyphs.items.len;
        try self.buffer_glyphs.append(self.allocator, buffer_glyph);

        // Store glyph info
        const glyph = Glyph{
            .index = glyph_index,
            .buffer_index = @intCast(buffer_index),
            .curve_count = buffer_glyph.count,
            .width = glyph_slot.*.metrics.width,
            .height = glyph_slot.*.metrics.height,
            .bearing_x = glyph_slot.*.metrics.horiBearingX,
            .bearing_y = glyph_slot.*.metrics.horiBearingY,
            .advance = glyph_slot.*.metrics.horiAdvance,
        };
        try self.glyphs.put(charcode, glyph);
    }

    fn convertContour(self: *Renderer, outline: *const ft.Outline, first_index: i16, last_index: i16, em_size: f32) !void {
        if (first_index == last_index) {
            return;
        }

        var d_index: i16 = 1;
        var actual_first = first_index;
        var actual_last = last_index;

        if (outline.flags & ft.OUTLINE_REVERSE_FILL != 0) {
            const tmp = actual_last;
            actual_last = actual_first;
            actual_first = tmp;
            d_index = -1;
        }

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
                first = makeMidpoint(convert(outline.points[@intCast(actual_first)], em_size), convert(outline.points[@intCast(actual_last)], em_size));
            }
        }

        var start = first;
        var control = first;
        var previous = first;
        var previous_tag = ft.CURVE_TAG_ON;

        var index = actual_first;
        while (index != actual_last + d_index) : (index += d_index) {
            const current = convert(outline.points[@intCast(index)], em_size);
            const current_tag = ft.c.FT_CURVE_TAG(outline.tags[@intCast(index)]);

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
                    const d = makeMidpoint(c0, c1);

                    try self.buffer_curves.append(self.allocator, makeCurve(b0, c0, d));
                    try self.buffer_curves.append(self.allocator, makeCurve(d, c1, b3));
                } else if (previous_tag == ft.CURVE_TAG_ON) {
                    // Linear segment
                    try self.buffer_curves.append(self.allocator, makeCurve(previous, makeMidpoint(previous, current), current));
                } else {
                    // Regular bezier curve
                    try self.buffer_curves.append(self.allocator, makeCurve(start, previous, current));
                }
                start = current;
                control = current;
            } else { // current_tag == ft.CURVE_TAG_CONIC
                if (previous_tag == ft.CURVE_TAG_ON) {
                    // Wait for third point
                } else {
                    // Create virtual on point
                    const mid = makeMidpoint(previous, current);
                    try self.buffer_curves.append(self.allocator, makeCurve(start, previous, mid));
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
            const d = makeMidpoint(c0, c1);

            try self.buffer_curves.append(self.allocator, makeCurve(b0, c0, d));
            try self.buffer_curves.append(self.allocator, makeCurve(d, c1, b3));
        } else if (previous_tag == ft.CURVE_TAG_ON) {
            // Linear segment
            try self.buffer_curves.append(self.allocator, makeCurve(previous, makeMidpoint(previous, first), first));
        } else {
            try self.buffer_curves.append(self.allocator, makeCurve(start, previous, first));
        }
    }

    /// Function currently is a no-op, since we
    /// are not using instanced rendering.
    pub fn updateBuffer(self: *Renderer) void {
        _ = self;
    }

    fn uploadGlyphsAndCurvesToTextures(self: *Renderer) !void {
        sg.destroyImage(self.glyph_texture);
        sg.destroyImage(self.curve_texture);

        // Ensure minimum size for glyph texture to avoid validation errors
        const glyph_count = @max(self.buffer_glyphs.items.len, 1);

        // Create glyph texture (RG32F format for start/count pairs)
        var glyph_desc: sg.ImageDesc = .{
            .label = "glyph texture",
            .width = @intCast(glyph_count),
            .height = 1,
            .pixel_format = .RG32F,
            .sample_count = 1,
            .num_mipmaps = 1,
        };

        // Convert BufferGlyph to packed format
        const glyph_data = try self.allocator.alloc([2]f32, glyph_count);
        defer self.allocator.free(glyph_data);

        if (self.buffer_glyphs.items.len > 0) {
            for (self.buffer_glyphs.items, 0..) |glyph, i| {
                glyph_data[i] = .{ @floatFromInt(glyph.start), @floatFromInt(glyph.count) };
            }
        } else {
            // Fill with default values if no glyphs
            glyph_data[0] = .{ 0.0, 0.0 };
        }

        glyph_desc.data.subimage[0][0] = sg.asRange(glyph_data);
        self.glyph_texture = sg.makeImage(glyph_desc);
        self.bind.images[shd_font.IMG_glyphs_tex] = self.glyph_texture;

        // Ensure minimum size for curve texture
        const curve_count = @max(self.buffer_curves.items.len, 1);
        const curve_width = curve_count * 3;

        // Create curve texture (RG32F format, 3 points per curve)
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

        if (self.buffer_curves.items.len > 0) {
            for (self.buffer_curves.items, 0..) |curve, i| {
                curve_data[i * 3 + 0] = .{ curve.x0, curve.y0 };
                curve_data[i * 3 + 1] = .{ curve.x1, curve.y1 };
                curve_data[i * 3 + 2] = .{ curve.x2, curve.y2 };
            }
        } else {
            // Fill with default values if no curves
            curve_data[0] = .{ 0.0, 0.0 };
            curve_data[1] = .{ 0.0, 0.0 };
            curve_data[2] = .{ 0.0, 0.0 };
        }

        curve_desc.data.subimage[0][0] = sg.asRange(curve_data);
        self.curve_texture = sg.makeImage(curve_desc);
        self.bind.images[shd_font.IMG_curves_tex] = self.curve_texture;
    }

    pub fn clear(self: *Renderer) void {
        self.text_elements.clearRetainingCapacity();
    }

    pub fn renderInPass(self: Renderer, vs_range: sg.Range) void {
        if (self.text_elements.items.len == 0) {
            return;
        }
        sg.applyPipeline(self.pip);

        var vertices = ArrayList(BufferVertex).initCapacity(self.allocator, 0) catch unreachable;
        defer vertices.deinit(self.allocator);

        var indices = ArrayList(i32).initCapacity(self.allocator, 0) catch unreachable;
        defer indices.deinit(self.allocator);

        for (self.text_elements.items) |text_element| {
            self.populateVertexArray(&vertices, &indices, text_element.x, text_element.y, text_element.text) catch |err| {
                std.log.err("[font] error while populating vertex array: {}", .{err});
                continue;
            };
        }

        if (vertices.items.len > MAX_ELEMENTS or indices.items.len > MAX_INDICES) {
            std.log.err("[font] vertex or index data size exceeds max size", .{});
            return;
        }
        sg.updateBuffer(self.bind.vertex_buffers[0], sg.asRange(vertices.items));
        sg.updateBuffer(self.bind.index_buffer, sg.asRange(indices.items));

        sg.applyBindings(self.bind);
        sg.applyUniforms(shd_font.UB_vs_params, vs_range);
        const fs_params = self.getColorFsParams();
        sg.applyUniforms(shd_font.UB_fs_params, sg.asRange(&fs_params));
        sg.draw(0, @intCast(indices.items.len), 1);
    }

    fn getColorFsParams(self: Renderer) shd_font.FsParams {
        return .{
            .text_color = [_]f32{
                self.color.r,
                self.color.g,
                self.color.b,
                self.color.a,
            },
        };
    }

    pub fn setWorldSize(self: *Renderer, world_size: f32) !void {
        if (world_size == self.world_size) return;
        self.world_size = world_size;

        if (!self.hinting) return;

        // Rebuild buffers for hinting
        self.em_size = world_size * 64.0;
        _ = self.font.face.setPixelSizes(0, @as(ft.UInt, @intFromFloat(@ceil(world_size)))) catch {
            std.log.err("[font] error while setting pixel size", .{});
        };

        self.buffer_glyphs.clearRetainingCapacity();
        self.buffer_curves.clearRetainingCapacity();

        var iterator = self.glyphs.iterator();
        while (iterator.next()) |entry| {
            const charcode = entry.key_ptr.*;
            const glyph = entry.value_ptr.*;

            _ = self.font.face.loadGlyph(glyph.index, self.load_flags) catch {
                std.log.err("[font] error while reloading glyph for character {}", .{charcode});
                continue;
            };

            try self.buildGlyph(charcode, glyph.index);
        }

        try self.uploadGlyphsAndCurvesToTextures();
    }

    pub fn cleanup(self: *Renderer) void {
        self.buffer_glyphs.deinit(self.allocator);
        self.buffer_curves.deinit(self.allocator);
        self.glyphs.deinit();
        self.font.deinit();
        self.text_elements.deinit(self.allocator);
    }

    fn populateVertexArray(self: Renderer, vertices: *ArrayList(BufferVertex), indices: *ArrayList(i32), x_in: f32, y_in: f32, text: []const u8) !void {
        const original_x = x_in;
        var x = x_in;
        var y = y_in;

        var previous: ft.UInt = 0;

        const utf8_view = std.unicode.Utf8View.init(text) catch |err| {
            std.log.err("Invalid UTF-8 text: {}", .{err});
            return;
        };
        var iterator = utf8_view.iterator();
        while (iterator.nextCodepoint()) |codepoint| {
            if (codepoint == '\r') continue;
            if (codepoint == '\n') {
                x = original_x;
                y -= self.getLineHeight();
                if (self.hinting) {
                    y = @round(y);
                }
                continue;
            }

            const glyph = self.glyphs.get(codepoint) orelse self.glyphs.get(0) orelse continue;
            if (previous != 0 and glyph.index != 0) {
                const kerning = self.font.face.getKerning(previous, glyph.index, self.kerning_mode) catch ft.Vector{ .x = 0, .y = 0 };
                x += @as(f32, @floatFromInt(kerning.x)) / self.em_size * self.world_size;
            }

            // Do not emit quad for empty glyphs (whitespace).
            if (glyph.curve_count > 0) {
                const d: ft.Pos = @as(ft.Pos, @intFromFloat(self.em_size * self.dilation));

                const u_0 = @as(f32, @floatFromInt(glyph.bearing_x - d)) / self.em_size;
                const v_0 = @as(f32, @floatFromInt(glyph.bearing_y - glyph.height - d)) / self.em_size;
                const u_1 = @as(f32, @floatFromInt(glyph.bearing_x + glyph.width + d)) / self.em_size;
                const v_1 = @as(f32, @floatFromInt(glyph.bearing_y + d)) / self.em_size;

                const x_0 = x + u_0 * self.world_size;
                const y_0 = y + v_0 * self.world_size;
                const x_1 = x + u_1 * self.world_size;
                const y_1 = y + v_1 * self.world_size;

                const base: i32 = @intCast(vertices.items.len);
                const buffer_index: i32 = @intCast(glyph.buffer_index);
                try vertices.append(self.allocator, BufferVertex{
                    .x = x_0,
                    .y = y_0,
                    .u = u_0,
                    .v = v_0,
                    .buffer_index = buffer_index,
                });
                try vertices.append(self.allocator, BufferVertex{
                    .x = x_1,
                    .y = y_0,
                    .u = u_1,
                    .v = v_0,
                    .buffer_index = buffer_index,
                });
                try vertices.append(self.allocator, BufferVertex{
                    .x = x_1,
                    .y = y_1,
                    .u = u_1,
                    .v = v_1,
                    .buffer_index = buffer_index,
                });
                try vertices.append(self.allocator, BufferVertex{
                    .x = x_0,
                    .y = y_1,
                    .u = u_0,
                    .v = v_1,
                    .buffer_index = buffer_index,
                });
                try indices.insertSlice(self.allocator, indices.items.len, &[_]i32{
                    base + 0, base + 1, base + 2,
                    base + 2, base + 3, base + 0,
                });
            }

            x += @as(f32, @floatFromInt(glyph.advance)) / self.em_size * self.world_size;
            previous = glyph.index;
        }
    }

    pub fn addLine(self: *Renderer, text_element: TextElement) void {
        // This adjustment is to make sure the text doesn't bleed
        // down into the next row
        const manual_adjust_y = self.getLineHeight() * 0.2;
        self.text_elements.append(self.allocator, .{
            .text = text_element.text,
            .x = text_element.x,
            // flip y-axis
            .y = -text_element.y + manual_adjust_y,
        }) catch |err| {
            std.log.err("[font] error while appending text element: {}", .{err});
            return;
        };
        self.prepareGlyphsForText(text_element.text) catch |err| {
            std.log.err("[font] error while preparing glyphs for text: {}", .{err});
            return;
        };
    }

    /// Get the advance width for a space character (useful for layout)
    pub fn getSpaceAdvance(self: *Renderer) f32 {
        const space_glyph = self.glyphs.get(32) orelse return 0.0;
        return @as(f32, @floatFromInt(space_glyph.advance)) / self.em_size * self.world_size;
    }

    fn prepareGlyphsForText(self: *Renderer, text: []const u8) !void {
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

            const glyph_index = self.font.codepointGlyphIndex(charcode) orelse continue;

            _ = self.font.face.loadGlyph(glyph_index, self.load_flags) catch {
                std.log.err("[font] error while loading glyph for character {}", .{charcode});
                continue;
            };

            try self.buildGlyph(charcode, glyph_index);
            changed = true;
        }

        if (changed) {
            try self.uploadGlyphsAndCurvesToTextures();
        }
    }

    /// Get the line height for the current font
    fn getLineHeight(self: Renderer) f32 {
        return @as(f32, @floatFromInt(self.font.face.face.*.height)) / @as(f32, @floatFromInt(self.font.face.face.*.units_per_EM)) * self.world_size;
    }
};

fn convert(v: ft.Vector, em: f32) [2]f32 {
    return .{
        @as(f32, @floatFromInt(v.x)) / em,
        @as(f32, @floatFromInt(v.y)) / em,
    };
}

fn makeMidpoint(a: [2]f32, b: [2]f32) [2]f32 {
    return .{ 0.5 * (a[0] + b[0]), 0.5 * (a[1] + b[1]) };
}

fn makeCurve(p0: [2]f32, p1: [2]f32, p2: [2]f32) BufferCurve {
    return BufferCurve{
        .x0 = p0[0],
        .y0 = p0[1],
        .x1 = p1[0],
        .y1 = p1[1],
        .x2 = p2[0],
        .y2 = p2[1],
    };
}
