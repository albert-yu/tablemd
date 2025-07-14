const std = @import("std");
const sokol = @import("sokol");
const shd_text = @import("text_shader");
const TrueType = @import("TrueType");
const zigimg = @import("zigimg");

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
};

const CharElement = struct {
    instance_position: [2]f32,
    glyph_size: [2]f32,
    tex_offset: [2]f32,
    tex_size: [2]f32,
    color: [4]f32,
    pixel_scale: f32,
};

const ATLAS_SIZE = 512;
const PIXEL_SCALE = 1.0 / 2048.0;
/// This is the font size when rasterized to the atlas
const FONT_SIZE = 48;
const CHAR_N = 1024;

pub const Renderer = struct {
    bind: sg.Bindings,
    pip: sg.Pipeline,
    count: u32,
    elements: [CHAR_N]CharElement,
    glyphs: [128]GlyphInfo,
    atlas_texture: sg.Image,
    font: ?TrueType,
    allocator: std.mem.Allocator,

    pub fn new(allocator: std.mem.Allocator) Renderer {
        return .{
            .bind = .{},
            .pip = .{},
            .count = 0,
            .elements = undefined,
            .glyphs = undefined,
            .atlas_texture = .{},
            .font = null,
            .allocator = allocator,
        };
    }

    pub fn setup(self: *Renderer) !void {
        // Load font
        const font_data = @embedFile("../fonts/SpaceMono-Regular.ttf");
        self.font = try TrueType.load(font_data);

        // Create atlas texture
        self.atlas_texture = try self.createAtlas();

        // Setup vertex buffer for quad (position and tex_coords interleaved)
        self.bind.vertex_buffers[0] = sg.makeBuffer(.{
            .data = sg.asRange(&[_]f32{
                0, 0, 0, 0, // bottom-left: position(0,0), tex_coords(0,0)
                1, 0, 1, 0, // bottom-right: position(1,0), tex_coords(1,0)
                0, 1, 0, 1, // top-left: position(0,1), tex_coords(0,1)
                1, 1, 1, 1, // top-right: position(1,1), tex_coords(1,1)
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

        // Setup instance buffer
        self.bind.vertex_buffers[1] = sg.makeBuffer(.{
            .size = CHAR_N * @sizeOf(CharElement),
            .usage = .{ .stream_update = true },
        });

        // Setup texture binding
        self.bind.images[shd_text.IMG_tex] = self.atlas_texture;
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
                l.attrs[shd_text.ATTR_text_tex_coords] = .{
                    .format = .FLOAT2,
                    .buffer_index = 0,
                    .offset = 8,
                };
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
        const max_height: u32 = FONT_SIZE + 8; // padding

        // Generate glyphs for ASCII characters 32-127
        for (32..128) |i| {
            const char = @as(u21, @intCast(i));
            const glyph_index = font.codepointGlyphIndex(char) orelse {
                // Set empty glyph info for missing characters
                self.glyphs[i] = GlyphInfo{
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
                continue;
            };

            // Use a buffer for the glyph bitmap
            var buffer = std.ArrayListUnmanaged(u8){};
            defer buffer.deinit(self.allocator);

            const dims = font.glyphBitmap(self.allocator, &buffer, glyph_index, scale, scale) catch {
                // Set empty glyph info for failed glyphs
                self.glyphs[i] = GlyphInfo{
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
                continue;
            };

            const width = @as(u32, @intCast(dims.width));
            const height = @as(u32, @intCast(dims.height));

            // Check if we need to move to next row
            if (x + width > ATLAS_SIZE) {
                x = 0;
                y += max_height;
                if (y + height > ATLAS_SIZE) {
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
            const bearing_x = @as(f32, @floatFromInt(hmetrics.left_side_bearing)) * scale;
            const bearing_y = 0.0; // Will be calculated from font metrics

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

        // Convert atlas data to PNG format and then extract raw data
        const png_rgba_data = try self.convertAtlasToPNGAndExtract(atlas_data);
        defer self.allocator.free(png_rgba_data);

        // Create texture with PNG-processed RGBA data
        var img_desc: sg.ImageDesc = .{
            .label = "text atlas image",
            .width = ATLAS_SIZE,
            .height = ATLAS_SIZE,
            .pixel_format = .RGBA8,
        };
        img_desc.data.subimage[0][0] = sg.asRange(png_rgba_data);
        return sg.makeImage(img_desc);
    }

    fn convertAtlasToPNGAndExtract(self: *Renderer, atlas_data: []const u8) ![]u8 {
        // Convert to PNG format and then extract raw RGBA data
        const png_data = try self.convertAtlasToPNG(atlas_data);
        defer self.allocator.free(png_data);

        // Create a temporary file to write PNG data
        const temp_path = "temp_atlas.png";
        {
            var file = try std.fs.cwd().createFile(temp_path, .{});
            defer file.close();
            try file.writeAll(png_data);
        }
        defer std.fs.cwd().deleteFile(temp_path) catch {};

        // Read back the PNG file as an image
        var image = try zigimg.Image.fromFilePath(self.allocator, temp_path);
        defer image.deinit();

        // Extract RGBA data
        const rgba_data = try self.allocator.alloc(u8, ATLAS_SIZE * ATLAS_SIZE * 4);
        const pixels = image.pixels.rgba32;

        for (0..ATLAS_SIZE) |y| {
            for (0..ATLAS_SIZE) |x| {
                const src_index = y * ATLAS_SIZE + x;
                const dst_index = (y * ATLAS_SIZE + x) * 4;
                const pixel = pixels[src_index];
                rgba_data[dst_index] = pixel.r;
                rgba_data[dst_index + 1] = pixel.g;
                rgba_data[dst_index + 2] = pixel.b;
                rgba_data[dst_index + 3] = pixel.a;
            }
        }

        return rgba_data;
    }

    fn convertAtlasToPNG(self: *Renderer, atlas_data: []const u8) ![]u8 {
        // Create zigimg image
        var image = try zigimg.Image.create(self.allocator, ATLAS_SIZE, ATLAS_SIZE, .rgba32);
        defer image.deinit();

        // Convert grayscale atlas to RGBA
        const pixels = image.pixels.rgba32;
        for (0..ATLAS_SIZE) |y| {
            for (0..ATLAS_SIZE) |x| {
                const src_index = y * ATLAS_SIZE + x;
                const dst_index = y * ATLAS_SIZE + x;
                const gray_value = atlas_data[src_index];
                pixels[dst_index] = zigimg.color.Rgba32{
                    .r = gray_value,
                    .g = gray_value,
                    .b = gray_value,
                    .a = gray_value, // Use grayscale value as alpha
                };
            }
        }

        // Allocate buffer for PNG encoding
        const write_buffer = try self.allocator.alloc(u8, ATLAS_SIZE * ATLAS_SIZE * 4 * 2); // Conservative estimate
        defer self.allocator.free(write_buffer);

        // Encode to PNG in memory
        const png_data = try image.writeToMemory(write_buffer, .{ .png = .{} });

        return self.allocator.dupe(u8, png_data);
    }

    pub fn addText(self: *Renderer, text: []const u8, x: f32, y: f32, color: [4]f32) void {
        var cursor_x = x;
        const cursor_y = y;

        // Calculate baseline - for now use a simple offset
        const baseline_offset = FONT_SIZE * 0.7; // Approximate baseline

        for (text) |char| {
            if (char < 32 or char > 127) continue;
            if (self.count >= CHAR_N) return;

            const glyph = self.glyphs[char];

            // Skip empty glyphs
            if (glyph.width == 0 or glyph.height == 0) {
                cursor_x += glyph.advance;
                continue;
            }

            // Position the glyph
            const glyph_x = cursor_x + glyph.bearing_x;
            const glyph_y = cursor_y - baseline_offset; // Use baseline offset

            const text_element = CharElement{
                .instance_position = .{ glyph_x, glyph_y },
                .glyph_size = .{ glyph.width, glyph.height },
                .tex_offset = .{ glyph.tex_x, glyph.tex_y },
                .tex_size = .{ glyph.tex_width, glyph.tex_height },
                .color = color,
                .pixel_scale = PIXEL_SCALE,
            };
            self.elements[self.count] = text_element;

            self.count += 1;
            cursor_x += glyph.advance;
        }
    }

    pub fn clear(self: *Renderer) void {
        self.count = 0;
    }

    pub fn updateBuffer(self: Renderer) void {
        sg.updateBuffer(self.bind.vertex_buffers[1], sg.asRange(self.elements[0..self.count]));
    }

    pub fn renderInPass(self: Renderer, vs_range: sg.Range) void {
        sg.applyPipeline(self.pip);
        sg.applyBindings(self.bind);
        sg.applyUniforms(shd_text.UB_vs_params, vs_range);
        sg.draw(0, 6, self.count);
    }

    fn writeAtlasToPNG(self: *Renderer, atlas_data: []const u8) !void {
        // Convert grayscale data to RGB for PNG
        var rgb_data = try self.allocator.alloc(u8, ATLAS_SIZE * ATLAS_SIZE * 3);
        defer self.allocator.free(rgb_data);

        for (atlas_data, 0..) |gray_value, i| {
            const rgb_index = i * 3;
            rgb_data[rgb_index] = gray_value; // R
            rgb_data[rgb_index + 1] = gray_value; // G
            rgb_data[rgb_index + 2] = gray_value; // B
        }

        // Create zigimg image
        var image = try zigimg.Image.create(self.allocator, ATLAS_SIZE, ATLAS_SIZE, .rgb24);
        defer image.deinit();

        // Copy data to image
        const pixels = image.pixels.rgb24;
        for (0..ATLAS_SIZE) |y| {
            for (0..ATLAS_SIZE) |x| {
                const src_index = (y * ATLAS_SIZE + x) * 3;
                const dst_index = y * ATLAS_SIZE + x;
                pixels[dst_index] = zigimg.color.Rgb24{
                    .r = rgb_data[src_index],
                    .g = rgb_data[src_index + 1],
                    .b = rgb_data[src_index + 2],
                };
            }
        }

        // Write to file
        try image.writeToFilePath("font_atlas.png", .{ .png = .{} });
        std.log.info("Font atlas written to font_atlas.png", .{});
    }

    pub fn cleanup(self: *Renderer) void {
        _ = self; // Font cleanup is handled automatically
    }
};
