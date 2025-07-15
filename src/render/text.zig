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
/// This is the font size when rasterized to the atlas
const FONT_SIZE = 48;
const CHAR_N = 1024;

pub const Renderer = struct {
    bind: sg.Bindings,
    pip: sg.Pipeline,
    texture: sg.Image,
    elements: [CHAR_N]CharElement,
    glyphs: [128]GlyphInfo,
    font: ?TrueType,
    allocator: std.mem.Allocator,

    pub fn new(allocator: std.mem.Allocator) Renderer {
        return .{
            .bind = .{},
            .pip = .{},
            .texture = .{},
            .allocator = allocator,
            .elements = undefined,
            .glyphs = undefined,
            .font = null,
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
                0, 0, 0, 0, // bottom-left, tex_coords(0,0)
                1, 0, 1, 0, // bottom-right, tex_coords(1,0)
                0, 1, 0, 1, // top-left, tex_coords(0,1)
                1, 1, 1, 1, // top-right, tex_coords(1,1)
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
        // // Write atlas to PNG file
        // self.writeAtlasToPNG(atlas_data) catch |err| {
        //     std.log.warn("Failed to write atlas to PNG: {}", .{err});
        // };
        return sg.makeImage(img_desc);
    }

    fn loadPNG(self: *Renderer) !sg.Image {
        // Load PNG file
        const img_bytes = @embedFile("font_atlas.png");
        var image = try zigimg.Image.fromMemory(self.allocator, img_bytes);
        defer image.deinit();

        // Convert to RGBA8 format
        const rgba_data = try self.allocator.alloc(u8, image.width * image.height * 4);
        defer self.allocator.free(rgba_data);

        // Convert image data to RGBA8
        switch (image.pixels) {
            .rgba32 => |pixels| {
                for (pixels, 0..) |pixel, i| {
                    const base_idx = i * 4;
                    rgba_data[base_idx] = pixel.r;
                    rgba_data[base_idx + 1] = pixel.g;
                    rgba_data[base_idx + 2] = pixel.b;
                    rgba_data[base_idx + 3] = pixel.a;
                }
            },
            .rgb24 => |pixels| {
                for (pixels, 0..) |pixel, i| {
                    const base_idx = i * 4;
                    rgba_data[base_idx] = pixel.r;
                    rgba_data[base_idx + 1] = pixel.g;
                    rgba_data[base_idx + 2] = pixel.b;
                    rgba_data[base_idx + 3] = 255; // full alpha
                }
            },
            .grayscale8 => |pixels| {
                for (pixels, 0..) |pixel, i| {
                    const base_idx = i * 4;
                    rgba_data[base_idx] = pixel.value;
                    rgba_data[base_idx + 1] = pixel.value;
                    rgba_data[base_idx + 2] = pixel.value;
                    rgba_data[base_idx + 3] = 255; // full alpha
                }
            },
            else => {
                return error.UnsupportedPixelFormat;
            },
        }

        // Create texture
        var img_desc: sg.ImageDesc = .{
            .label = "text image",
            .width = @intCast(image.width),
            .height = @intCast(image.height),
            .pixel_format = .RGBA8,
            .sample_count = 1,
            .num_mipmaps = 1,
        };
        img_desc.data.subimage[0][0] = sg.asRange(rgba_data);

        return sg.makeImage(img_desc);
    }

    pub fn renderInPass(self: Renderer, vs_range: sg.Range) void {
        sg.applyPipeline(self.pip);
        sg.applyBindings(self.bind);
        sg.applyUniforms(shd_text.UB_vs_params, vs_range);
        sg.draw(0, 6, 1);
    }

    pub fn cleanup(self: *Renderer) void {
        _ = self;
    }
};
