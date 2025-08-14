const std = @import("std");
const Build = std.Build;
const sokol = @import("sokol");
const freetype_build = @import("vendor/freetype/build.zig");

const Options = struct {
    mod: *Build.Module,
    dep_sokol: *Build.Dependency,
    mod_freetype: *Build.Module,
};

const ShaderModule = struct {
    module_name: []const u8,
    input_file: []const u8,
    output_file: []const u8,
};

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const dep_sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });
    const dep_zm = b.dependency("zm", .{
        .target = target,
        .optimize = optimize,
    });
    const dep_zigimg = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });

    const mod_markdown = b.createModule(.{
        .root_source_file = b.path("vendor/markdown/markdown.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create FreeType module
    const mod_freetype = b.createModule(.{
        .root_source_file = b.path("vendor/freetype/freetype.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod_freetype.addIncludePath(b.path("vendor/freetype/include"));

    const mod_root = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "sokol",
                .module = dep_sokol.module("sokol"),
            },
            .{
                .name = "zm",
                .module = dep_zm.module("zm"),
            },
            .{
                .name = "zigimg",
                .module = dep_zigimg.module("zigimg"),
            },
            .{
                .name = "freetype",
                .module = mod_freetype,
            },
            .{
                .name = "markdown",
                .module = mod_markdown,
            },
            .{
                .name = "quad_shader",
                .module = try createShaderModule(b, dep_sokol, .{
                    .module_name = "quad_shader",
                    .input_file = "src/shaders/quad.glsl",
                    .output_file = "quad_shader.zig",
                }),
            },
            .{
                .name = "rect_shader",
                .module = try createShaderModule(b, dep_sokol, .{
                    .module_name = "rect_shader",
                    .input_file = "src/shaders/rect.glsl",
                    .output_file = "rect_shader.zig",
                }),
            },
            .{
                .name = "text_shader",
                .module = try createShaderModule(b, dep_sokol, .{
                    .module_name = "text_shader",
                    .input_file = "src/shaders/text.glsl",
                    .output_file = "text_shader.zig",
                }),
            },
            .{
                .name = "font_shader",
                .module = try createShaderModule(b, dep_sokol, .{
                    .module_name = "font_shader",
                    .input_file = "src/shaders/font.glsl",
                    .output_file = "font_shader.zig",
                }),
            },
        },
    });

    // special case handling for native vs web build
    const opts = Options{
        .mod = mod_root,
        .dep_sokol = dep_sokol,
        .mod_freetype = mod_freetype,
    };
    if (target.result.cpu.arch.isWasm()) {
        try buildWeb(b, opts);
    } else {
        try buildNative(b, opts);
    }
}

// this is the regular build for all native platforms, nothing surprising here
fn buildNative(b: *Build, opts: Options) !void {
    const exe = b.addExecutable(.{
        .name = "root",
        .root_module = opts.mod,
    });
    const target = opts.mod.resolved_target.?;
    const optimize = opts.mod.optimize.?;
    const freetype_lib = try freetype_build.build(b, .{
        .target = target,
        .optimize = optimize,
        .emsdk = null,
    });
    exe.linkLibrary(freetype_lib);
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    b.step("run", "Run root").dependOn(&run.step);
}

// for web builds, the Zig code needs to be built into a library and linked with the Emscripten linker
fn buildWeb(b: *Build, opts: Options) !void {
    const lib = b.addStaticLibrary(.{
        .name = "root",
        .root_module = opts.mod,
    });
    const emsdk = opts.dep_sokol.builder.dependency("emsdk", .{});
    const target = opts.mod.resolved_target.?;
    const optimize = opts.mod.optimize.?;
    const freetype_lib = try freetype_build.build(b, .{
        .target = target,
        .optimize = optimize,
        .emsdk = emsdk,
    });

    lib.linkLibrary(freetype_lib);

    const cache_result = freetype_build.initEmsdkCache(b, emsdk);
    if (cache_result.cache_init_step) |c_init_step| {
        freetype_lib.step.dependOn(c_init_step);
    }
    opts.mod_freetype.addSystemIncludePath(cache_result.include_path);

    // create a build step which invokes the Emscripten linker
    const link_step = try sokol.emLinkStep(b, .{
        .lib_main = lib,
        .target = opts.mod.resolved_target.?,
        .optimize = opts.mod.optimize.?,
        .emsdk = emsdk,
        .use_webgl2 = true,
        .use_emmalloc = true,
        .use_filesystem = false,
        .shell_file_path = b.path("src/web/shell.html"),
        .extra_args = &.{
            "-sUSE_OFFSET_CONVERTER",
            "-sALLOW_MEMORY_GROWTH=1",
            // Need to include Sokol's original entry point (main),
            // because specifying this flag overrides the original
            "-sEXPORTED_FUNCTIONS=_main,_handle_paste_from_web,_malloc,_free,_handle_deserialize,_request_serialize,_clear_tables",
            "-sEXPORTED_RUNTIME_METHODS=UTF8ToString,stringToUTF8,HEAPU8",
            "--js-library=src/web/library.js",
        },
    });

    // attach Emscripten linker output to default install step
    b.getInstallStep().dependOn(&link_step.step);
    // ...and a special run step to start the web build output via 'emrun'
    const run = sokol.emRunStep(b, .{ .name = "root", .emsdk = emsdk });
    run.step.dependOn(&link_step.step);
    b.step("run", "Run root").dependOn(&run.step);
}

// compile shader via sokol-shdc
fn createShaderModule(b: *Build, dep_sokol: *Build.Dependency, mod: ShaderModule) !*Build.Module {
    const mod_sokol = dep_sokol.module("sokol");
    const dep_shdc = dep_sokol.builder.dependency("shdc", .{});
    return sokol.shdc.createModule(b, mod.module_name, mod_sokol, .{
        .shdc_dep = dep_shdc,
        .input = mod.input_file,
        .output = mod.output_file,
        .slang = .{
            .glsl410 = true,
            .glsl300es = true,
            .hlsl4 = true,
            .metal_macos = true,
            .wgsl = true,
        },
    });
}
