const std = @import("std");
const Build = std.Build;
const sokol = @import("sokol");

const Options = struct {
    mod: *Build.Module,
    dep_sokol: *Build.Dependency,
    freetype_lib: *Build.Step.Compile,
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

    // Create FreeType static library
    const freetype_lib = try createFreeTypeLib(b, target, optimize);

    const mod_markdown = b.createModule(.{
        .root_source_file = b.path("vendor/markdown/markdown.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create FreeType module
    const mod_freetype = b.createModule(.{
        .root_source_file = b.path("src/freetype.zig"),
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
        },
    });

    // special case handling for native vs web build
    const opts = Options{ .mod = mod_root, .dep_sokol = dep_sokol, .freetype_lib = freetype_lib };
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
    exe.linkLibrary(opts.freetype_lib);
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
    lib.linkLibrary(opts.freetype_lib);

    // create a build step which invokes the Emscripten linker
    const emsdk = opts.dep_sokol.builder.dependency("emsdk", .{});
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

// Create FreeType static library
fn createFreeTypeLib(b: *Build, target: Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !*Build.Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = "freetype",
        .target = target,
        .optimize = optimize,
    });

    // Add include directories
    lib.addIncludePath(b.path("vendor/freetype/include"));
    lib.addIncludePath(b.path("vendor/freetype/src"));

    // Common compilation flags
    const c_flags = &.{
        "-DFT2_BUILD_LIBRARY",
        "-DFT_CONFIG_OPTION_ERROR_STRINGS",
        "-std=c99",
    };

    // Base module - core functionality
    lib.addCSourceFile(.{
        .file = b.path("vendor/freetype/src/base/ftbase.c"),
        .flags = c_flags,
    });
    lib.addCSourceFile(.{
        .file = b.path("vendor/freetype/src/base/ftinit.c"),
        .flags = c_flags,
    });
    lib.addCSourceFile(.{
        .file = b.path("vendor/freetype/src/base/ftsystem.c"),
        .flags = c_flags,
    });

    // Font drivers we need
    lib.addCSourceFile(.{
        .file = b.path("vendor/freetype/src/truetype/truetype.c"),
        .flags = c_flags,
    });
    lib.addCSourceFile(.{
        .file = b.path("vendor/freetype/src/sfnt/sfnt.c"),
        .flags = c_flags,
    });
    lib.addCSourceFile(.{
        .file = b.path("vendor/freetype/src/cff/cff.c"),
        .flags = c_flags,
    });
    lib.addCSourceFile(.{
        .file = b.path("vendor/freetype/src/type1/type1.c"),
        .flags = c_flags,
    });
    lib.addCSourceFile(.{
        .file = b.path("vendor/freetype/src/cid/type1cid.c"),
        .flags = c_flags,
    });
    lib.addCSourceFile(.{
        .file = b.path("vendor/freetype/src/pfr/pfr.c"),
        .flags = c_flags,
    });
    lib.addCSourceFile(.{
        .file = b.path("vendor/freetype/src/type42/type42.c"),
        .flags = c_flags,
    });
    lib.addCSourceFile(.{
        .file = b.path("vendor/freetype/src/winfonts/winfnt.c"),
        .flags = c_flags,
    });
    lib.addCSourceFile(.{
        .file = b.path("vendor/freetype/src/pcf/pcf.c"),
        .flags = c_flags,
    });
    lib.addCSourceFile(.{
        .file = b.path("vendor/freetype/src/bdf/bdf.c"),
        .flags = c_flags,
    });

    // Rasterizers
    lib.addCSourceFile(.{
        .file = b.path("vendor/freetype/src/smooth/smooth.c"),
        .flags = c_flags,
    });
    lib.addCSourceFile(.{
        .file = b.path("vendor/freetype/src/raster/raster.c"),
        .flags = c_flags,
    });
    lib.addCSourceFile(.{
        .file = b.path("vendor/freetype/src/sdf/sdf.c"),
        .flags = c_flags,
    });
    lib.addCSourceFile(.{
        .file = b.path("vendor/freetype/src/svg/svg.c"),
        .flags = c_flags,
    });

    // Hinting modules
    lib.addCSourceFile(.{
        .file = b.path("vendor/freetype/src/autofit/autofit.c"),
        .flags = c_flags,
    });
    lib.addCSourceFile(.{
        .file = b.path("vendor/freetype/src/pshinter/pshinter.c"),
        .flags = c_flags,
    });

    // PostScript support
    lib.addCSourceFile(.{
        .file = b.path("vendor/freetype/src/psaux/psaux.c"),
        .flags = c_flags,
    });
    lib.addCSourceFile(.{
        .file = b.path("vendor/freetype/src/psnames/psnames.c"),
        .flags = c_flags,
    });

    // Compression support
    lib.addCSourceFile(.{
        .file = b.path("vendor/freetype/src/gzip/ftgzip.c"),
        .flags = c_flags,
    });
    lib.addCSourceFile(.{
        .file = b.path("vendor/freetype/src/lzw/ftlzw.c"),
        .flags = c_flags,
    });

    // Debug support
    lib.addCSourceFile(.{
        .file = b.path("vendor/freetype/src/base/ftdebug.c"),
        .flags = c_flags,
    });

    // Base extensions we need
    lib.addCSourceFile(.{
        .file = b.path("vendor/freetype/src/base/ftbitmap.c"),
        .flags = c_flags,
    });
    lib.addCSourceFile(.{
        .file = b.path("vendor/freetype/src/base/ftglyph.c"),
        .flags = c_flags,
    });
    lib.addCSourceFile(.{
        .file = b.path("vendor/freetype/src/base/ftmm.c"),
        .flags = c_flags,
    });

    lib.linkLibC();

    return lib;
}
