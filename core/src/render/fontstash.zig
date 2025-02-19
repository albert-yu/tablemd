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

pub const Context = c.FONScontext;

// const backend = sg.queryBackend();

const SfonsDesc = struct {
    width: i32,
    height: i32,
    /// TODO: parameterize this
    allocator: std.mem.Allocator,
};

const Sfons = struct {
    desc: SfonsDesc,
    shd: sg.Shader,
    pip: sg.Pipeline,
    img: sg.Image,
    smp: sg.Sampler,
    cur_width: i32,
    cur_height: i32,
    img_dirty: bool,
};

pub fn create(desc: SfonsDesc) ?*Context {
    var params: c.FONSparams = .{
        .width = desc.width,
        .height = desc.height,
        .flags = c.FONS_ZERO_TOPLEFT,
        .renderCreate = renderCreate,
    };
    return c.fonsCreateInternal(&params);
}

fn renderCreate(data: Sfons, width: i32, height: i32) i32 {
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
        data.smp = sgl.makeSampler(smp_desc);
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
