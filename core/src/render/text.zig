const sokol = @import("sokol");
const shd = @import("../shaders/text.glsl.zig");
const math = @import("../math.zig");
const font = @import("../render/fonts/space-mono-regular/msdf.zig").font;

const Mat4 = math.Mat4;
const Vec2 = math.Vec2;

const font_atlas = @embedFile("../render/fonts/space-mono-regular/atlas.png");
const atlas_w = 512;
const atlas_h = 512;

const char_count = font.chars.len;

const TEXT_N = 1024;
const CHAR_N = 1024;

const sg = sokol.gfx;
const sgl = sokol.gl;

const TextElement = struct {
    transform: Mat4,
    color: [4]f32,
    pixel_scale: f32,
    char: [3]f32,
};

const CharElement = struct {
    tex_offset: Vec2,
    tex_extent: Vec2,
    size: Vec2,
    offset: Vec2,
};

pub const Renderer = struct {
    bind: sg.Bindings,
    pip: sg.Pipeline,

    char_elements: [CHAR_N]CharElement,
    text_elements: [TEXT_N]TextElement,

    pub fn new() Renderer {
        return .{
            .bind = .{},
            .pip = .{},
        };
    }

    pub fn setup(self: *Renderer) void {
        const BUF_vert = 0;
        const BUF_text = 1;
        const BUF_char = 2;

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

        self.bind.vertex_buffers[BUF_char] = sg.makeBuffer(.{
            .usage = .STREAM,
            .size = char_count * @sizeOf(CharElement),
        });

        var pip: sg.PipelineDesc = .{
            .shader = sg.makeShader(shd.textShaderDesc(sg.queryBackend())),
            .layout = init: {
                var l = sg.VertexLayoutState{};
                l.buffers[BUF_text].step_func = .PER_INSTANCE;
                l.buffers[BUF_char].step_func = .PER_INSTANCE;
                l.attrs[shd.ATTR_text_position] = .{
                    .format = .FLOAT4,
                    .buffer_index = BUF_vert,
                };
                l.attrs[shd.ATTR_text_tex_offset] = .{
                    .format = .FLOAT2,
                    .buffer_index = BUF_char,
                };
                l.attrs[shd.ATTR_text_tex_extent] = .{
                    .format = .FLOAT2,
                    .buffer_index = BUF_char,
                };
                l.attrs[shd.ATTR_text_size] = .{
                    .format = .FLOAT2,
                    .buffer_index = BUF_char,
                };
                l.attrs[shd.ATTR_text_offset] = .{
                    .format = .FLOAT2,
                    .buffer_index = BUF_char,
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
                    .format = .FLOAT1,
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
        pip.colors[0].blend = .{
            .enabled = true,
            .src_factor_alpha = .SRC_ALPHA,
            .dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
            .src_factor_rgb = .SRC_ALPHA,
            .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
        };

        self.pip = pip;

        // populate char elements
        const u = 1.0 / font.common.scale_w;
        const v = 1.0 / font.common.scale_h;
        for (0..char_count) |i| {
            const char = font.chars[i];
            self.char_elements[i] = .{
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

    pub fn cleanup(self: *Renderer) void {
        sg.deallocImage(self.bind.images[shd.IMG_text]);
    }
};
