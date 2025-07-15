const std = @import("std");
const sokol = @import("sokol");
const shd_png = @import("png_shader");
const zigimg = @import("zigimg");

const sg = sokol.gfx;

pub const Renderer = struct {
    bind: sg.Bindings,
    pip: sg.Pipeline,
    texture: sg.Image,
    allocator: std.mem.Allocator,

    pub fn new(allocator: std.mem.Allocator) Renderer {
        return .{
            .bind = .{},
            .pip = .{},
            .texture = .{},
            .allocator = allocator,
        };
    }

    pub fn setup(self: *Renderer) !void {
        // Load PNG image
        self.texture = try self.loadPNG("src/render/font_atlas.png");

        // Setup vertex buffer for quad (position and tex_coords interleaved)
        self.bind.vertex_buffers[0] = sg.makeBuffer(.{
            .data = sg.asRange(&[_]f32{
                -1, -1, 0, 0, // bottom-left, tex_coords(0,0)
                1, -1, 1, 0, // bottom-right, tex_coords(1,0)
                -1, 1, 0, 1, // top-left, tex_coords(0,1)
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
        self.bind.images[shd_png.IMG_tex] = self.texture;
        self.bind.samplers[shd_png.SMP_smp] = sg.makeSampler(.{
            .label = "png sampler",
            .min_filter = .LINEAR,
            .mag_filter = .LINEAR,
            .wrap_u = .CLAMP_TO_EDGE,
            .wrap_v = .CLAMP_TO_EDGE,
        });

        // Create pipeline
        var pip_desc: sg.PipelineDesc = .{
            .shader = sg.makeShader(shd_png.pngShaderDesc(sg.queryBackend())),
            .layout = init: {
                var l = sg.VertexLayoutState{};
                l.attrs[shd_png.ATTR_png_position] = .{
                    .format = .FLOAT2,
                    .buffer_index = 0,
                    .offset = 0,
                };
                l.attrs[shd_png.ATTR_png_tex_coords] = .{
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

    fn loadPNG(self: *Renderer, path: []const u8) !sg.Image {
        // Load PNG file
        var image = try zigimg.Image.fromFilePath(self.allocator, path);
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
            .label = "png image",
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
        sg.applyUniforms(shd_png.UB_vs_params, vs_range);
        sg.draw(0, 6, 1);
    }

    pub fn cleanup(self: *Renderer) void {
        _ = self;
    }
};
