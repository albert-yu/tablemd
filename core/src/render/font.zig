const sokol = @import("sokol");
const sfons = @import("sfons.zig");
const std = @import("std");

const sg = sokol.gfx;
const sgl = sokol.gl;
const sapp = sokol.app;

const font_atlas = @embedFile("../render/fonts/space-mono-regular/atlas.png");
const font_atlas_raw: [*c]u8 = @ptrCast(@constCast(font_atlas));
const atlas_w = 512;
const atlas_h = 512;

pub const Renderer = struct {
    ctx: ?*sfons.Context,
    dpi_scale: f32,
    font: c_int,

    pub fn init(allocator: std.mem.Allocator, dpi_scale: f32) !Renderer {
        const ctx = try sfons.create(allocator, .{
            .width = atlas_w,
            .height = atlas_h,
        });
        const font = sfons.addFontMem(ctx, "Space Mono", font_atlas_raw, font_atlas.len, 0);
        return Renderer{
            .ctx = ctx,
            .dpi_scale = dpi_scale,
            .font = font,
        };
    }

    pub fn beforeRenderPass(self: *Renderer) void {
        const white = sfons.rgba(255, 255, 255, 255);
        sgl.defaults();
        sgl.matrixModeProjection();
        sgl.ortho(0, sapp.widthf(), sapp.heightf(), 0, -1, 1);
        sfons.clearState(self.ctx);

        var lh: f32 = 0.0;

        if (self.font != sfons.FONS_INVALID) {
            sfons.setFont(self.ctx, self.font);
            sfons.setSize(self.ctx, 124.0 * self.dpi_scale);
            sfons.vertMetrics(self.ctx, null, null, &lh);
            sfons.setColor(self.ctx, white);
            _ = sfons.drawText(self.ctx, 0, 0, "Hi there", null);
        }
        sfons.flush(self.ctx);
    }

    pub fn renderInPass(_: *Renderer) void {
        sgl.drawLayer(1);
    }

    pub fn deinit(self: *Renderer, allocator: std.mem.Allocator) void {
        sfons.destroy(allocator, self.ctx);
    }
};

fn roundPow2(v: f32) i32 {
    var vi: u32 = @floor(v) - 1;
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        vi |= (vi >> (@as(u32, 1) << i));
    }
    return @intCast(vi + 1);
}
