const std = @import("std");
const sokol = @import("sokol");
const shd_text = @import("text_shader");
const zigimg = @import("zigimg");
const TrueType = @import("TrueType");

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
    color: [4]f32,
    pixel_scale: f32,
};

/// Atlas size in pixels
const ATLAS_SIZE = 512;

/// This is the font size when rasterized to the atlas
const FONT_SIZE = 48;

/// Maximum number of characters that can be rendered
const CHAR_N = 1024;

/// Might be able to be derived from the GRID_N and GRID_DENSITY,
/// but chosen with trial and error for now
const PIXEL_SCALE = 1.0 / 1500.0;

pub const Renderer = struct {
    bind: sg.Bindings,
    pip: sg.Pipeline,
    texture: sg.Image,
    elements: [CHAR_N]CharElement,
    count: usize,
    glyphs: [128]GlyphInfo,
    font: ?TrueType,
    allocator: std.mem.Allocator,

    pub fn new(allocator: std.mem.Allocator) Renderer {
        return .{
            .bind = .{},
            .pip = .{},
            .texture = .{},
            .elements = undefined,
            .count = 0,
            .glyphs = undefined,
            .font = null,
            .allocator = allocator,
        };
    }

    pub fn setup(self: *Renderer) !void {
        // Load font
        const font_data = @embedFile("../fonts/SpaceMono-Regular.ttf");
        self.font = try TrueType.load(font_data);
        self.texture = try self.createAtlas();

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
                .compare = .ALWAYS,
                .write_enabled = false,
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

    pub fn addText(self: *Renderer, text: []const u8, x: f32, y: f32) void {
        // this is a hack to make sure the text doesn't bleed
        // down into the next row
        const manual_adjust_y = -10.0;
        const scaled_x = x / PIXEL_SCALE;
        const scaled_y = y / PIXEL_SCALE + manual_adjust_y;
        var current_x = scaled_x;

        for (text) |char| {
            if (char >= 32 and char <= 127) {
                self.addChar(char, current_x, scaled_y);
                const glyph = self.glyphs[char];
                current_x += glyph.advance;
            }
        }
    }

    fn addChar(self: *Renderer, char: u8, x: f32, y: f32) void {
        if (self.count == CHAR_N) {
            return;
        }
        if (char < 32 or char > 127) {
            return;
        }
        const glyph = self.glyphs[char];
        if (glyph.width > 0 and glyph.height > 0) {
            self.elements[self.count] = CharElement{
                .instance_position = .{
                    x + glyph.bearing_x,
                    y + glyph.bearing_y,
                },
                .glyph_size = .{ glyph.width, glyph.height },
                // tex offset/size are normalized to [0, 1]
                .tex_offset = .{ glyph.tex_x, glyph.tex_y },
                .tex_size = .{ glyph.tex_width, glyph.tex_height },
                .color = .{ 1.0, 1.0, 1.0, 1.0 },
                .pixel_scale = PIXEL_SCALE,
            };
            self.count += 1;
        }
    }

    fn createAtlas(self: *Renderer) !sg.Image {
        var atlas_data = try self.allocator.alloc(u8, ATLAS_SIZE * ATLAS_SIZE);
        defer self.allocator.free(atlas_data);

        // Clear atlas
        @memset(atlas_data, 0);

        const font = self.font.?;
        const scale = font.scaleForPixelHeight(@as(f32, FONT_SIZE));

        const u: f32 = 1.0 / @as(f32, ATLAS_SIZE);
        const v: f32 = 1.0 / @as(f32, ATLAS_SIZE);

        var x: u32 = 0;
        var y: u32 = 0;
        const row_height: u32 = FONT_SIZE + 8; // padding

        // Handle space character (32) separately - no bitmap needed, just advance metrics
        const space_glyph_index = font.codepointGlyphIndex(32);
        if (space_glyph_index) |glyph_idx| {
            const hmetrics = font.glyphHMetrics(glyph_idx);
            const advance = @as(f32, @floatFromInt(hmetrics.advance_width)) * scale;
            self.glyphs[32] = GlyphInfo{
                .advance = advance,
                .bearing_x = 0,
                .bearing_y = 0,
                .width = 0,
                .height = 0,
                .tex_x = 0,
                .tex_y = 0,
                .tex_width = 0,
                .tex_height = 0,
            };
        } else {
            // Fallback for missing space character
            self.glyphs[32] = GlyphInfo{
                .advance = @as(f32, FONT_SIZE) * 0.25, // Quarter of font size as fallback
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

        // Generate glyphs for ASCII characters 33-127
        for (33..128) |i| {
            const char = @as(u21, @intCast(i));
            const glyph_index = font.codepointGlyphIndex(char) orelse {
                // Set empty glyph info for missing characters
                self.glyphs[i] = GlyphInfo.empty();
                continue;
            };

            // Use a buffer for the glyph bitmap
            var buffer = std.ArrayListUnmanaged(u8){};
            defer buffer.deinit(self.allocator);

            const dims = font.glyphBitmap(self.allocator, &buffer, glyph_index, scale, scale) catch |err| {
                const as_char = @as(u8, @intCast(char));
                std.log.err("Failed to rasterize glyph \"{c}\": {}", .{ as_char, err });
                // Set empty glyph info for failed glyphs
                self.glyphs[i] = GlyphInfo.empty();
                continue;
            };

            const width = @as(u32, @intCast(dims.width));
            const height = @as(u32, @intCast(dims.height));
            const off_x = dims.off_x;
            const off_y = dims.off_y;

            // Check if we need to move to next row
            if (x + width > ATLAS_SIZE) {
                x = 0;
                y += row_height;
                if (y + row_height > ATLAS_SIZE) {
                    return error.AtlasFull;
                }
            }

            // Copy bitmap to atlas
            const pixels = buffer.items;
            for (0..height) |row| {
                const src_offset = row * width;
                const dst_offset = (y + row) * ATLAS_SIZE + x;
                if (src_offset + width <= pixels.len and dst_offset + width <= atlas_data.len) {
                    @memcpy(atlas_data[dst_offset .. dst_offset + width], pixels[src_offset .. src_offset + width]);
                }
            }

            // Get horizontal metrics
            const hmetrics = font.glyphHMetrics(glyph_index);

            const advance = @as(f32, @floatFromInt(hmetrics.advance_width)) * scale;
            // Use off_x and off_y from dims for proper glyph positioning
            const bearing_x = @as(f32, @floatFromInt(off_x));
            const bearing_y = @as(f32, @floatFromInt(off_y));

            // Store glyph info
            self.glyphs[i] = GlyphInfo{
                .advance = advance,
                .bearing_x = bearing_x,
                .bearing_y = bearing_y,
                .width = @as(f32, @floatFromInt(width)),
                .height = @as(f32, @floatFromInt(height)),
                .tex_x = @as(f32, @floatFromInt(x)) * u,
                .tex_y = @as(f32, @floatFromInt(y)) * v,
                .tex_width = @as(f32, @floatFromInt(width)) * u,
                .tex_height = @as(f32, @floatFromInt(height)) * v,
            };

            x += width + 1; // padding
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

    pub fn updateBuffer(self: Renderer) void {
        sg.updateBuffer(self.bind.vertex_buffers[1], sg.asRange(self.elements[0..self.count]));
    }

    pub fn clear(self: *Renderer) void {
        self.count = 0;
    }

    pub fn renderInPass(self: Renderer, vs_range: sg.Range) void {
        sg.applyPipeline(self.pip);
        sg.applyBindings(self.bind);
        sg.applyUniforms(shd_text.UB_vs_params, vs_range);
        sg.draw(0, 6, @intCast(self.count));
    }

    pub fn cleanup(self: *Renderer) void {
        _ = self;
    }
};
