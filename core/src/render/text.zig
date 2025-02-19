const std = @import("std");
const sokol = @import("sokol");
const shd = @import("../shaders/text.glsl.zig");
const math = @import("../math.zig");
const msdf = @import("../render/fonts/space-mono-regular/msdf.zig");
const MsdfFont = @import("font.zig").MsdfFont;
const font = msdf.font;
const MsdfChar = msdf.Char;

const sg = sokol.gfx;
const sgl = sokol.gl;

const Mat4 = math.Mat4;
const Vec3 = math.Vec3;
const Vec2 = math.Vec2;

const font_atlas = @embedFile("../render/fonts/space-mono-regular/atlas.png");
const atlas_w = 512;
const atlas_h = 512;

const char_count = font.chars.len;

/// Total character count for text elements
const TEXT_N = 1024 * 1024;

/// Charset size
const CHARSET_N = 1024; // TODO: bigger?

const PIXEL_SCALE = 1.0 / 2048.0;

const TextElement = struct {
    transform: Mat4,
    color: [4]f32,
    pixel_scale: f32,
    /// x,y = position,
    /// z = index in charset
    ///
    /// WebGPU has a way of binding an entire array of vec3s
    /// within this struct, but I'm not sure if it's possible
    /// to do this in Sokol GLSL.
    char: [3]f32,
};

/// In char set
const CharElement = struct {
    tex_offset: Vec2,
    tex_extent: Vec2,
    size: Vec2,
    offset: Vec2,
};

const Text = struct {
    data: []const u8,
    position: Vec2,
};

const TextMeasurements = struct {
    width: f32,
    height: f32,
    line_widths: std.ArrayList(f32),
    printed_char_count: u32,
};

const FormatTextOptions = struct {
    centered: ?bool,
    pixel_scale: ?f32,
    color: ?[4]f32,
};

const MsdfText = struct {
    element: TextElement,
    dirty: bool,
    measurements: TextMeasurements,
    font: MsdfFont,

    pub fn new(f: MsdfFont) MsdfText {
        return .{
            .buffer_array = undefined,
            .dirty = true,
            .measurements = undefined,
            .font = f,
        };
    }
};

pub const Renderer = struct {
    bind: sg.Bindings,
    pip: sg.Pipeline,

    msdf_font: MsdfFont,
    charset: [CHARSET_N]CharElement,
    text_elements: [TEXT_N]TextElement,
    char_count: u32,

    pub fn new() Renderer {
        return .{
            .count = 0,
            .bind = .{},
            .pip = .{},
            .char_elements = undefined,
            .text_elements = undefined,
        };
    }

    pub fn setup(self: *Renderer) void {
        const BUF_vert = 0;
        const BUF_text = 1;
        const BUF_charset = 2;

        // set up quad
        self.bind.vertex_buffers[BUF_vert] = sg.makeBuffer(.{
            .data = sg.asRange(&[_]f32{
                0, -1,
                1, -1,
                0, 0,
                1, 0,
            }),
        });
        self.bind.index_buffer = sg.makeBuffer(.{
            .type = .INDEXBUFFER,
            .data = sg.asRange(&[_]u16{
                0, 1, 2,
                1, 2, 3,
            }),
        });

        // set up font data
        self.bind.vertex_buffers[BUF_text] = sg.makeBuffer(.{
            .size = TEXT_N * @sizeOf(TextElement),
            .usage = .STREAM,
        });

        // set up font data
        self.bind.vertex_buffers[BUF_charset] = sg.makeBuffer(.{
            .usage = .STREAM,
            .size = char_count * @sizeOf(CharElement),
        });

        var pipDesc: sg.PipelineDesc = .{
            .shader = sg.makeShader(shd.textShaderDesc(sg.queryBackend())),
            .layout = init: {
                var l = sg.VertexLayoutState{};
                l.buffers[BUF_text].step_func = .PER_INSTANCE;
                l.buffers[BUF_charset].step_func = .PER_INSTANCE;
                l.attrs[shd.ATTR_text_position] = .{
                    .format = .FLOAT4,
                    .buffer_index = BUF_vert,
                };
                l.attrs[shd.ATTR_text_tex_offset] = .{
                    .format = .FLOAT2,
                    .buffer_index = BUF_charset,
                };
                l.attrs[shd.ATTR_text_tex_extent] = .{
                    .format = .FLOAT2,
                    .buffer_index = BUF_charset,
                };
                l.attrs[shd.ATTR_text_size] = .{
                    .format = .FLOAT2,
                    .buffer_index = BUF_charset,
                };
                l.attrs[shd.ATTR_text_offset] = .{
                    .format = .FLOAT2,
                    .buffer_index = BUF_charset,
                };
                l.attrs[shd.ATTR_text_transform0] = .{
                    .format = .FLOAT4,
                    .buffer_index = BUF_text,
                };
                l.attrs[shd.ATTR_text_transform1] = .{
                    .format = .FLOAT4,
                    .buffer_index = BUF_text,
                };
                l.attrs[shd.ATTR_text_transform2] = .{
                    .format = .FLOAT4,
                    .buffer_index = BUF_text,
                };
                l.attrs[shd.ATTR_text_transform3] = .{
                    .format = .FLOAT4,
                    .buffer_index = BUF_text,
                };
                l.attrs[shd.ATTR_text_color0] = .{
                    .format = .FLOAT4,
                    .buffer_index = BUF_text,
                };
                l.attrs[shd.ATTR_text_scale] = .{
                    .format = .FLOAT,
                    .buffer_index = BUF_text,
                };
                l.attrs[shd.ATTR_text_char] = .{
                    .format = .FLOAT3,
                    .buffer_index = BUF_text,
                };
                break :init l;
            },
            .index_type = .UINT16,
            .depth = .{
                .compare = .LESS_EQUAL,
                .write_enabled = true,
            },
        };
        pipDesc.colors[0].blend = .{
            .enabled = true,
            .src_factor_alpha = .SRC_ALPHA,
            .dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
            .src_factor_rgb = .SRC_ALPHA,
            .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
        };

        self.pip = sg.makePipeline(pipDesc);

        // populate char elements
        const u = 1.0 / font.common.scale_w;
        const v = 1.0 / font.common.scale_h;
        for (0..char_count) |i| {
            const char = font.chars[i];
            self.charset[i] = .{
                .tex_offset = Vec2.new(char.x * u, char.y * v),
                .tex_extent = Vec2.new(char.width * u, char.height * v),
                .size = Vec2.new(char.width, char.height),
                .offset = Vec2.new(char.xoffset, char.yoffset),
            };
        }

        // set up atlas texture
        self.bind.images[shd.IMG_tex] = sg.allocImage();
        var imgDesc: sg.ImageDesc = .{
            .width = atlas_w,
            .height = atlas_h,
            .pixel_format = .RGBA8,
        };
        imgDesc.data.subimage[0][0] = .{
            .ptr = font_atlas,
            .size = atlas_w * atlas_h * 4,
        };
        sg.initImage(self.bind.images[shd.IMG_tex], imgDesc);

        self.bind.samplers[shd.SMP_smp] = sg.makeSampler(.{
            .min_filter = .LINEAR,
            .mag_filter = .LINEAR,
        });
    }

    pub fn add(self: *Renderer, text: Text) void {
        if (text.data.len + self.char_count > TEXT_N) {
            return;
        }
        const transform = Mat4.translate(Vec3.new(text.position.x, text.position.y, 0.0));
        // TODO: figure out why flipping the y-axis is necessary
        transform.m[1][1] = -1.0 * transform.m[1][1];
        self.char_count += text.data.len;
    }

    pub fn renderInPass(self: Renderer, vs_range: sg.Range) void {
        sg.applyPipeline(self.pip);
        sg.applyBindings(self.bind);
        sg.applyUniforms(shd.UB_vs_params, vs_range);
        sg.applyUniforms(shd.UB_fs_params, sg.asRange(&computeFsParams()));
        sg.draw(0, 6, self.char_count);
    }

    pub fn cleanup(self: *Renderer) void {
        sg.deallocImage(self.bind.images[shd.IMG_tex]);
    }

    fn formatText(self: *Renderer, allocator: std.mem.Allocator, value: []const u8, options: FormatTextOptions) !MsdfText {
        var measurements: TextMeasurements = undefined;
        var text_buffer: TextElement = undefined;
        measurements = try measureText(self.allocator, self.msdf_font, value, &text_buffer);
    }
};

fn computeFsParams() shd.FsParams {
    return .{
        .texture_size = [_]f32{ atlas_w, atlas_h },
    };
}

fn measureText(allocator: std.mem.Allocator, msdf_font: MsdfFont, text: []const u8, text_element: ?*TextElement) !TextMeasurements {
    var max_width: f32 = 0;
    var line_widths = std.ArrayList(f32).init(allocator);

    var text_offset_x: f32 = 0;
    var text_offset_y: f32 = 0;
    var line: u32 = 0;
    var printed_char_count: u32 = 0;

    const CHAR_NEWLINE: u8 = 10;
    const CHAR_CR: u8 = 13;
    const CHAR_SPACE: u8 = 32;

    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        const char_code = text[i];
        // const next_char_code = if (i < text.len - 1) text[i + 1] else @as(u8, 0);

        switch (char_code) {
            CHAR_NEWLINE => {
                try line_widths.append(text_offset_x);
                line += 1;
                max_width = @max(max_width, text_offset_x);
                text_offset_x = 0;
                text_offset_y -= msdf_font.line_height;
            },
            CHAR_CR => {
                // Skip carriage return
            },
            CHAR_SPACE => {
                text_offset_x += msdf_font.getXAdvance(char_code);
            },
            else => {
                if (text_element) |el| {
                    const ch = msdf_font.getChar(char_code);
                    el.char[0] = text_offset_x;
                    el.char[1] = text_offset_y;
                    el.char[2] = ch.index;
                }
                text_offset_x += msdf_font.getXAdvance(char_code);
                printed_char_count += 1;
            },
        }
    }

    try line_widths.append(text_offset_x);
    max_width = @max(max_width, text_offset_x);

    const line_widths_lengthf: usize = @floatFromInt(line_widths.items.len);

    return TextMeasurements{
        .width = max_width,
        .height = line_widths_lengthf * msdf_font.line_height,
        .line_widths = line_widths,
        .printed_char_count = printed_char_count,
    };
}
