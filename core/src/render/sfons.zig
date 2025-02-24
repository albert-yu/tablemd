/// This file is a Zig translation of
/// https://github.com/floooh/sokol/blob/b0aa42fa061759908a6c68029703e0988a854b53/util/sokol_fontstash.h
const c = @cImport({
    @cInclude("fontstash.h");
});
const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const sgl = sokol.gl;
const shd = @import("../shaders/sfons.glsl.zig");

const int = c_int;

pub const FONS_INVALID = c.FONS_INVALID;

pub const Context = c.FONScontext;

const FONS_VERTEX_COUNT = 1024;
const FONS_MAX_STATES = 20;

const FONSatlasNode = extern struct {
    x: c_short,
    y: c_short,
    width: c_short,
};

const FONSatlas = extern struct {
    width: c_int,
    height: c_int,
    nodes: [*c]FONSatlasNode,
};

const FONSstate = extern struct {
    font: c_int,
    align_: c_int,
    size: f32,
    color: c_uint,
    blur: f32,
    spacing: f32,
};
// const FONSstate = opaque {};

/// Translated from
/// https://github.com/memononen/fontstash/blob/b5ddc9741061343740d85d636d782ed3e07cf7be/src/fontstash.h#L426
///
/// ```c
/// struct FONScontext
/// {
/// 	FONSparams params;
/// 	float itw,ith;
/// 	unsigned char* texData;
/// 	int dirtyRect[4];
/// 	FONSfont** fonts;
/// 	FONSatlas* atlas;
/// 	int cfonts;
/// 	int nfonts;
/// 	float verts[FONS_VERTEX_COUNT*2];
/// 	float tcoords[FONS_VERTEX_COUNT*2];
/// 	unsigned int colors[FONS_VERTEX_COUNT];
/// 	int nverts;
/// 	unsigned char* scratch;
/// 	int nscratch;
/// 	FONSstate states[FONS_MAX_STATES];
/// 	int nstates;
/// 	void (*handleError)(void* uptr, int error, int val);
/// 	void* errorUptr;
/// };
/// ```
const FONScontext = extern struct {
    params: c.FONSparams,
    itw: f32,
    ith: f32,
    texData: [*c]u8,
    dirtyRect: [4]int,
    fonts: [*]*c.struct_FONSfont_1,
    atlas: *FONSatlas,
    cfonts: int,
    nfonts: int,
    verts: [FONS_VERTEX_COUNT * 2]f32,
    tcoords: [FONS_VERTEX_COUNT * 2]f32,
    colors: [FONS_VERTEX_COUNT]u32,
    nverts: int,
    scratch: [*]u8,
    nscratch: int,
    states: [FONS_MAX_STATES]FONSstate,
    nstates: int,
    handleError: ?*anyopaque,
    errorUptr: ?*anyopaque,
};

// const backend = sg.queryBackend();

const SfonsDesc = struct {
    width: int,
    height: int,
};

const Sfons = struct {
    desc: SfonsDesc,
    shd: sg.Shader,
    pip: sgl.Pipeline,
    img: sg.Image,
    smp: sg.Sampler,
    cur_width: int,
    cur_height: int,
    img_dirty: bool,
};

// fons helpers, passed in from fontstash.h

pub fn setSize(ctx: ?*Context, size: f32) void {
    c.fonsSetSize(ctx, size);
}

pub fn setColor(ctx: ?*Context, color: u32) void {
    c.fonsSetColor(ctx, color);
}

pub fn clearState(ctx: ?*Context) void {
    c.fonsClearState(ctx);
}

pub fn setFont(ctx: ?*Context, font: int) void {
    c.fonsSetFont(ctx, font);
}

pub fn vertMetrics(ctx: ?*Context, ascender: [*c]f32, descender: [*c]f32, lineh: [*c]f32) void {
    c.fonsVertMetrics(ctx, ascender, descender, lineh);
}

pub fn drawText(ctx: ?*Context, x: f32, y: f32, text: [*c]const u8, end: [*c]const u8) f32 {
    return c.fonsDrawText(ctx, x, y, text, end);
}

pub fn textBounds(ctx: ?*Context, x: f32, y: f32, text: [*c]const u8, end: [*c]const u8, bounds: [*c]f32) void {
    c.fonsTextBounds(ctx, x, y, text, end, bounds);
}

pub fn addFontMem(ctx: ?*Context, name: [*c]const u8, data: [*c]u8, ndata: c_int, free_data: c_int) c_int {
    return c.fonsAddFontMem(ctx, name, data, ndata, free_data);
}

// end fons helpers

pub fn create(allocator: std.mem.Allocator, desc: SfonsDesc) !?*Context {
    var sfons = try allocator.alloc(Sfons, 1);
    const ptr: ?*anyopaque = @ptrCast(&sfons);
    var params: c.FONSparams = .{
        .width = desc.width,
        .height = desc.height,
        .flags = c.FONS_ZERO_TOPLEFT,
        .renderCreate = renderCreate,
        .renderResize = renderResize,
        .renderUpdate = renderUpdate,
        .renderDraw = renderDraw,
        .renderDelete = renderDelete,
        .userPtr = ptr,
    };
    return c.fonsCreateInternal(&params);
}

pub fn destroy(allocator: std.mem.Allocator, ctx: ?*Context) void {
    c.fonsDeleteInternal(ctx);
    const sfons_ctx = castContext(ctx);
    const sfons = castSfons(sfons_ctx.params.userPtr);
    allocator.destroy(sfons);
}

pub fn flush(ctx: ?*Context) void {
    const fons_ctx: *FONScontext = castContext(ctx);
    var sfons: *Sfons = castSfons(fons_ctx.params.userPtr);
    if (sfons.img_dirty) {
        sfons.img_dirty = false;
        var data: sg.ImageData = .{};
        data.subimage[0][0].ptr = fons_ctx.texData;
        const size: usize = @intCast(sfons.cur_width * sfons.cur_height);
        data.subimage[0][0].size = size;
        sg.updateImage(sfons.img, data);
    }
}

pub fn rgba(r: u8, g: u8, b: u8, a: u8) u32 {
    return (@as(u32, a) << 24) |
        (@as(u32, b) << 16) |
        (@as(u32, g) << 8) |
        @as(u32, r);
}

fn renderCreate(user_ptr: ?*anyopaque, width: int, height: int) callconv(.C) int {
    var data: *Sfons = castSfons(user_ptr);
    if (data.shd.id == sg.invalid_id) {
        const backend = sg.queryBackend();
        var shd_desc = shd.sfontstashShaderDesc(backend);
        shd_desc.attrs[0].glsl_name = "position";
        shd_desc.attrs[1].glsl_name = "texcoord0";
        shd_desc.attrs[2].glsl_name = "color0";
        shd_desc.attrs[3].glsl_name = "psize";
        shd_desc.attrs[0].hlsl_sem_name = "TEXCOORD";
        shd_desc.attrs[0].hlsl_sem_index = 0;
        shd_desc.attrs[1].hlsl_sem_name = "TEXCOORD";
        shd_desc.attrs[1].hlsl_sem_index = 1;
        shd_desc.attrs[2].hlsl_sem_name = "TEXCOORD";
        shd_desc.attrs[2].hlsl_sem_index = 2;
        shd_desc.attrs[3].hlsl_sem_name = "TEXCOORD";
        shd_desc.attrs[3].hlsl_sem_index = 3;
        shd_desc.uniform_blocks[0].stage = .VERTEX;
        shd_desc.uniform_blocks[0].size = 128;
        shd_desc.uniform_blocks[0].hlsl_register_b_n = 0;
        shd_desc.uniform_blocks[0].msl_buffer_n = 0;
        shd_desc.uniform_blocks[0].wgsl_group0_binding_n = 0;
        shd_desc.uniform_blocks[0].glsl_uniforms[0].glsl_name = "vs_params";
        shd_desc.uniform_blocks[0].glsl_uniforms[0].type = .FLOAT4;
        shd_desc.uniform_blocks[0].glsl_uniforms[0].array_count = 8;
        shd_desc.images[0].stage = .FRAGMENT;
        shd_desc.images[0].image_type = ._2D;
        shd_desc.images[0].sample_type = .FLOAT;
        shd_desc.images[0].hlsl_register_t_n = 0;
        shd_desc.images[0].msl_texture_n = 0;
        shd_desc.images[0].wgsl_group1_binding_n = 64;
        shd_desc.samplers[0].stage = .FRAGMENT;
        shd_desc.samplers[0].sampler_type = .FILTERING;
        shd_desc.samplers[0].hlsl_register_s_n = 0;
        shd_desc.samplers[0].msl_sampler_n = 0;
        shd_desc.samplers[0].wgsl_group1_binding_n = 80;
        shd_desc.image_sampler_pairs[0].stage = .FRAGMENT;
        shd_desc.image_sampler_pairs[0].glsl_name = "tex_smp";
        shd_desc.image_sampler_pairs[0].image_slot = 0;
        shd_desc.image_sampler_pairs[0].sampler_slot = 0;
        shd_desc.label = "fontstash-shader";
        data.shd = sg.makeShader(shd_desc);
        // switch (backend) {}
    }
    if (data.pip.id == sg.invalid_id) {
        var pip_desc = sg.PipelineDesc{
            .shader = data.shd,
        };
        pip_desc.colors[0] = .{
            .blend = .{
                .enabled = true,
                .src_factor_rgb = .SRC_ALPHA,
                .dst_factor_rgb = .DST_ALPHA,
            },
        };
        data.pip = sgl.makePipeline(pip_desc);
    }
    if (data.smp.id == sg.invalid_id) {
        const smp_desc = sg.SamplerDesc{
            .min_filter = .LINEAR,
            .mag_filter = .LINEAR,
        };
        data.smp = sg.makeSampler(smp_desc);
    }
    if (data.img.id != sg.invalid_id) {
        sg.destroyImage(data.img);
        data.img.id = sg.invalid_id;
    }
    data.cur_width = width;
    data.cur_height = height;

    data.img = sg.makeImage(.{
        .width = data.cur_width,
        .height = data.cur_height,
        .usage = .DYNAMIC,
        .pixel_format = .R8,
    });

    return 1;
}

fn renderResize(user_ptr: ?*anyopaque, width: int, height: int) callconv(.C) int {
    return renderCreate(user_ptr, width, height);
}

fn renderUpdate(user_ptr: ?*anyopaque, _: [*c]int, _: [*c]const u8) callconv(.C) void {
    var data: *Sfons = castSfons(user_ptr);
    data.img_dirty = true;
}

fn renderDraw(user_ptr: ?*anyopaque, verts: [*c]const f32, tcoords: [*c]const f32, colors: [*c]const c_uint, nverts: int) callconv(.C) void {
    const data: *Sfons = castSfons(user_ptr);
    if (nverts == 0) {
        return;
    }
    sgl.enableTexture();
    sgl.texture(data.img, data.smp);
    sgl.pushPipeline();
    sgl.loadPipeline(data.pip);
    sgl.beginTriangles();
    for (0..@intCast(nverts)) |i| {
        sgl.v2fT2fC1i(verts[2 * i + 0], verts[2 * i + 1], tcoords[2 * i + 0], tcoords[2 * i + 1], colors[i]);
    }
    sgl.end();
    sgl.popPipeline();
    sgl.disableTexture();
}

fn renderDelete(user_ptr: ?*anyopaque) callconv(.C) void {
    const data: *Sfons = castSfons(user_ptr);
    if (data.img.id != sg.invalid_id) {
        sg.destroyImage(data.img);
        data.img.id = sg.invalid_id;
    }
    if (data.smp.id != sg.invalid_id) {
        sg.destroySampler(data.smp);
        data.smp.id = sg.invalid_id;
    }
    if (data.pip.id != sg.invalid_id) {
        sgl.destroyPipeline(data.pip);
        data.pip.id = sg.invalid_id;
    }
    if (data.shd.id != sg.invalid_id) {
        sg.destroyShader(data.shd);
        data.shd.id = sg.invalid_id;
    }
}

fn castSfons(ptr: ?*anyopaque) *Sfons {
    return @alignCast(@ptrCast(ptr));
}

fn castContext(ptr: ?*anyopaque) *FONScontext {
    return @alignCast(@ptrCast(ptr));
}
