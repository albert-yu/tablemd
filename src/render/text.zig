const std = @import("std");
const sokol = @import("sokol");
const shd_text = @import("text_shader");
const zigimg = @import("zigimg");
const freetype = @import("freetype");
const ArrayList = std.ArrayListUnmanaged;

const sg = sokol.gfx;

const GlyphInfo = struct {
    advance: f32,
    bearing_x: f32,
    bearing_y: f32,
    width: f32,
    height: f32,
    tex_x: f32,
    tex_y: f32,
    tex_width: f32,
    tex_height: f32,

    pub fn empty() GlyphInfo {
        return .{
            .advance = 0,
            .bearing_x = 0,
            .bearing_y = 0,
            .width = 0,
            .height = 0,
            .tex_x = 0,
            .tex_y = 0,
            .tex_width = 0,
            .tex_height = 0,
        };
    }
};

const CharElement = struct {
    instance_position: [2]f32,
    glyph_size: [2]f32,
    tex_offset: [2]f32,
    tex_size: [2]f32,
    color: sg.Color,
    pixel_scale: f32,
};

pub const TextElement = struct {
    text: []const u8,
    x: f32,
    y: f32,
    color: sg.Color,
};

/// Atlas size in pixels
const ATLAS_SIZE = 1024;

/// This is the font size when rasterized to the atlas
const FONT_SIZE = 48;

/// Maximum number of characters that can be rendered
const CHAR_N = 1024;

/// Number of glyphs to support (expanded for Unicode)
const GLYPH_COUNT = 1024;

/// Might be able to be derived from the GRID_N and GRID_DENSITY,
/// but chosen with trial and error for now
const PIXEL_SCALE = 1.0 / 2048.0;

pub const Renderer = struct {
    bind: sg.Bindings,
    pip: sg.Pipeline,
    texture: sg.Image,
    elements: ArrayList(CharElement),
    /// Maps Unicode codepoints to glyph info
    glyph_map: std.HashMap(u21, GlyphInfo, std.hash_map.AutoContext(u21), std.hash_map.default_max_load_percentage),
    font: ?freetype.Font,
    allocator: std.mem.Allocator,

    pub fn new(allocator: std.mem.Allocator) Renderer {
        return .{
            .bind = .{},
            .pip = .{},
            .texture = .{},
            .elements = ArrayList(CharElement).initCapacity(allocator, 0) catch unreachable,
            .glyph_map = std.HashMap(u21, GlyphInfo, std.hash_map.AutoContext(u21), std.hash_map.default_max_load_percentage).init(allocator),
            .font = null,
            .allocator = allocator,
        };
    }

    /// Returns the advance width
    pub fn setup(self: *Renderer) !f32 {
        // Load font
        const font_data = @embedFile("../fonts/SpaceMono-Regular.ttf");
        self.font = try freetype.load(font_data);
        self.texture = try self.createAtlas();
        const space_glyph = self.glyph_map.get(32) orelse GlyphInfo.empty();
        const advance_width = space_glyph.advance * PIXEL_SCALE;

        // Setup vertex buffer for quad (position and tex_coords interleaved)
        self.bind.vertex_buffers[0] = sg.makeBuffer(.{
            .data = sg.asRange(&[_]f32{
                0, 0, // bottom-left
                1, 0, // bottom-right
                0, 1, // top-left
                1, 1, // top-right
            }),
        });

        // Setup index buffer
        self.bind.index_buffer = sg.makeBuffer(.{
            .usage = .{ .index_buffer = true },
            .data = sg.asRange(&[_]u16{
                0, 1, 2,
                1, 2, 3,
            }),
        });

        // Setup instance buffer for character data
        self.bind.vertex_buffers[1] = sg.makeBuffer(.{
            .usage = .{ .stream_update = true },
            .size = @sizeOf(CharElement) * CHAR_N,
        });

        // Setup texture binding
        self.bind.images[shd_text.IMG_tex] = self.texture;
        self.bind.samplers[shd_text.SMP_smp] = sg.makeSampler(.{
            .label = "text sampler",
            .min_filter = .LINEAR,
            .mag_filter = .LINEAR,
            .wrap_u = .CLAMP_TO_EDGE,
            .wrap_v = .CLAMP_TO_EDGE,
        });

        // Create pipeline
        var pip_desc: sg.PipelineDesc = .{
            .shader = sg.makeShader(shd_text.textShaderDesc(sg.queryBackend())),
            .layout = init: {
                var l = sg.VertexLayoutState{};
                l.buffers[1].step_func = .PER_INSTANCE;
                l.attrs[shd_text.ATTR_text_position] = .{
                    .format = .FLOAT2,
                    .buffer_index = 0,
                    .offset = 0,
                };
                // Instance attributes (per-instance)
                l.attrs[shd_text.ATTR_text_instance_position] = .{
                    .format = .FLOAT2,
                    .buffer_index = 1,
                };
                l.attrs[shd_text.ATTR_text_glyph_size] = .{
                    .format = .FLOAT2,
                    .buffer_index = 1,
                };
                l.attrs[shd_text.ATTR_text_tex_offset] = .{
                    .format = .FLOAT2,
                    .buffer_index = 1,
                };
                l.attrs[shd_text.ATTR_text_tex_size] = .{
                    .format = .FLOAT2,
                    .buffer_index = 1,
                };
                l.attrs[shd_text.ATTR_text_color] = .{
                    .format = .FLOAT4,
                    .buffer_index = 1,
                };
                l.attrs[shd_text.ATTR_text_pixel_scale] = .{
                    .format = .FLOAT,
                    .buffer_index = 1,
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
        return advance_width;
    }

    /// Assumes that all characters are on the same line
    pub fn addLine(self: *Renderer, element: TextElement) void {
        const text = element.text;
        const x = element.x;
        const y = element.y;
        const color = element.color;

        // this is a hack to make sure the text doesn't bleed
        // down into the next row
        const manual_adjust_y = -FONT_SIZE - 10.0;
        const scaled_x = x / PIXEL_SCALE;
        const scaled_y = y / PIXEL_SCALE + manual_adjust_y;
        var current_x = scaled_x;

        // Decode UTF-8 text
        const utf8_view = std.unicode.Utf8View.init(text) catch |err| {
            std.log.err("Invalid UTF-8 text: {}", .{err});
            return;
        };
        var iterator = utf8_view.iterator();

        while (iterator.nextCodepoint()) |codepoint| {
            self.addChar(codepoint, current_x, scaled_y, color);
            if (self.glyph_map.get(codepoint)) |glyph| {
                current_x += glyph.advance;
            }
        }
    }

    fn addChar(self: *Renderer, codepoint: u21, x: f32, y: f32, color: sg.Color) void {
        const glyph = self.glyph_map.get(codepoint) orelse {
            // Use fallback character (replacement character U+FFFD or space)
            const fallback = self.glyph_map.get(32) orelse return; // Use space as fallback
            if (fallback.width > 0 and fallback.height > 0) {
                const char_element = CharElement{
                    .instance_position = .{
                        x + fallback.bearing_x,
                        y + fallback.bearing_y,
                    },
                    .glyph_size = .{ fallback.width, fallback.height },
                    .tex_offset = .{ fallback.tex_x, fallback.tex_y },
                    .tex_size = .{ fallback.tex_width, fallback.tex_height },
                    .color = color,
                    .pixel_scale = PIXEL_SCALE,
                };
                self.elements.append(self.allocator, char_element) catch |err| {
                    std.log.err("Failed to append character element: {}", .{err});
                };
            }
            return;
        };

        if (glyph.width > 0 and glyph.height > 0) {
            const char_element = CharElement{
                .instance_position = .{
                    x + glyph.bearing_x,
                    y + glyph.bearing_y,
                },
                .glyph_size = .{ glyph.width, glyph.height },
                // tex offset/size are normalized to [0, 1]
                .tex_offset = .{ glyph.tex_x, glyph.tex_y },
                .tex_size = .{ glyph.tex_width, glyph.tex_height },
                .color = color,
                .pixel_scale = PIXEL_SCALE,
            };
            self.elements.append(self.allocator, char_element) catch |err| {
                std.log.err("Failed to append character element: {}", .{err});
                return;
            };
        }
    }

    fn createAtlas(self: *Renderer) !sg.Image {
        const atlas_data = try self.allocator.alloc(u8, ATLAS_SIZE * ATLAS_SIZE);
        defer self.allocator.free(atlas_data);

        // Clear atlas
        @memset(atlas_data, 0);

        const font = self.font.?;
        try font.setPixelHeight(@as(f32, FONT_SIZE));

        const u: f32 = 1.0 / @as(f32, ATLAS_SIZE);
        const v: f32 = 1.0 / @as(f32, ATLAS_SIZE);

        var x: u32 = 0;
        var y: u32 = 0;
        const row_height: u32 = FONT_SIZE + 8; // padding

        // Define Unicode ranges to support
        const unicode_ranges = [_]struct { start: u21, end: u21 }{
            .{ .start = 32, .end = 126 }, // Basic Latin (ASCII printable)
            .{ .start = 160, .end = 255 }, // Latin-1 Supplement
            .{ .start = 0x0100, .end = 0x017F }, // Latin Extended-A
            .{ .start = 0x0180, .end = 0x024F }, // Latin Extended-B
            .{ .start = 0x2010, .end = 0x206F }, // General Punctuation
            .{ .start = 0x2070, .end = 0x209F }, // Superscripts and Subscripts
            .{ .start = 0x20A0, .end = 0x20CF }, // Currency Symbols
            .{ .start = 0x2100, .end = 0x214F }, // Letterlike Symbols
        };

        // Handle space character (32) separately
        try self.addGlyphToAtlas(32, font, atlas_data, &x, &y, row_height, u, v);

        // Generate glyphs for supported Unicode ranges
        for (unicode_ranges) |range| {
            var codepoint = range.start;
            if (codepoint == 32) codepoint = 33; // Skip space, already handled

            while (codepoint <= range.end) : (codepoint += 1) {
                try self.addGlyphToAtlas(codepoint, font, atlas_data, &x, &y, row_height, u, v);

                // Prevent atlas overflow by limiting total glyphs
                if (self.glyph_map.count() >= GLYPH_COUNT) {
                    break;
                }
            }

            if (self.glyph_map.count() >= GLYPH_COUNT) {
                break;
            }
        }

        // Create texture
        var img_desc: sg.ImageDesc = .{
            .label = "text atlas image",
            .width = ATLAS_SIZE,
            .height = ATLAS_SIZE,
            .pixel_format = .R8,
            .sample_count = 1,
            .num_mipmaps = 1,
        };
        img_desc.data.subimage[0][0] = sg.asRange(atlas_data);
        return sg.makeImage(img_desc);
    }

    fn addGlyphToAtlas(self: *Renderer, codepoint: u21, font: freetype.Font, atlas_data: []u8, x: *u32, y: *u32, row_height: u32, u: f32, v: f32) !void {
        const glyph_index = font.codepointGlyphIndex(codepoint) orelse {
            // Set empty glyph info for missing characters
            try self.glyph_map.put(codepoint, GlyphInfo.empty());
            return;
        };

        // Handle space character specially (no bitmap)
        if (codepoint == 32) {
            const hmetrics = font.glyphFontMetrics(glyph_index);
            const advance = @as(f32, @floatFromInt(hmetrics.hori_advance));
            try self.glyph_map.put(32, GlyphInfo{
                .advance = advance,
                .bearing_x = 0,
                .bearing_y = 0,
                .width = 0,
                .height = 0,
                .tex_x = 0,
                .tex_y = 0,
                .tex_width = 0,
                .tex_height = 0,
            });
            return;
        }

        // Use a buffer for the glyph bitmap
        var buffer = std.ArrayListUnmanaged(u8){};
        defer buffer.deinit(self.allocator);

        const dims = font.glyphBitmap(self.allocator, &buffer, glyph_index, 1.0, 1.0) catch |err| {
            const non_breaking_space = 0x00A0;
            if (codepoint != non_breaking_space) {
                // we know this one is missing, so don't log it
                std.log.warn("Failed to rasterize glyph U+{X}: {}", .{ codepoint, err });
            }
            // Set empty glyph info for failed glyphs
            try self.glyph_map.put(codepoint, GlyphInfo.empty());
            return;
        };

        const width = @as(u32, @intCast(@max(0, dims.width)));
        const height = @as(u32, @intCast(@max(0, dims.height)));

        // Check if we need to move to next row
        if (x.* + width > ATLAS_SIZE) {
            x.* = 0;
            y.* += row_height;
            if (y.* + row_height > ATLAS_SIZE) {
                std.log.warn("Atlas full, skipping glyph U+{X}", .{codepoint});
                try self.glyph_map.put(codepoint, GlyphInfo.empty());
                return;
            }
        }

        // Copy bitmap to atlas
        const pixels = buffer.items;
        for (0..height) |row| {
            const src_offset = row * width;
            const dst_offset = (y.* + row) * ATLAS_SIZE + x.*;
            if (src_offset + width <= pixels.len and dst_offset + width <= atlas_data.len) {
                @memcpy(atlas_data[dst_offset .. dst_offset + width], pixels[src_offset .. src_offset + width]);
            }
        }

        // Get horizontal metrics
        const metrics = font.glyphFontMetrics(glyph_index);
        const advance = @as(f32, @floatFromInt(metrics.hori_advance));
        const bearing_x = @as(f32, @floatFromInt(metrics.hori_bearing_x));
        const bearing_y = @as(f32, @floatFromInt(metrics.vert_bearing_y));

        // Store glyph info
        try self.glyph_map.put(codepoint, GlyphInfo{
            .advance = advance,
            .bearing_x = bearing_x,
            .bearing_y = bearing_y,
            .width = @as(f32, @floatFromInt(width)),
            .height = @as(f32, @floatFromInt(height)),
            .tex_x = @as(f32, @floatFromInt(x.*)) * u,
            .tex_y = @as(f32, @floatFromInt(y.*)) * v,
            .tex_width = @as(f32, @floatFromInt(width)) * u,
            .tex_height = @as(f32, @floatFromInt(height)) * v,
        });

        x.* += width + 1; // padding
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
        sg.applyUniforms(shd_text.UB_vs_params, vs_range);
        sg.draw(0, 6, @intCast(self.elements.items.len));
    }

    pub fn cleanup(self: *Renderer) void {
        self.elements.deinit(self.allocator);
        self.glyph_map.deinit();
        if (self.font) |font| {
            font.deinit();
        }
    }
};
