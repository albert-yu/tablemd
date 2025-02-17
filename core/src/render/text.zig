const sokol = @import("sokol");
const shd = @import("../shaders/text.glsl.zig");
const math = @import("../math.zig");
const font = @import("../render/fonts/space-mono-regular/msdf.zig").font;

const Mat4 = math.Mat4;
const Vec2 = math.Vec2;

const font_atlas = @embedFile("../render/fonts/space-mono-regular/atlas.png");
const atlas_w = 512;
const atlas_h = 512;

const TEXT_N = 1024;

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

    pub fn new() Renderer {
        return .{
            .bind = .{},
            .pip = .{},
        };
    }

    pub fn setup(self: *Renderer) void {
        // set up quad
        self.bind.vertex_buffers[0] = sg.makeBuffer(.{
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
        self.bind.vertex_buffers[1] = sg.makeBuffer(.{
            .size = TEXT_N * @sizeOf(TextElement),
            .usage = .STREAM,
        });

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
