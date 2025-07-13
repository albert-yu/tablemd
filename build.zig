const std = @import("std");
const Build = std.Build;
const sokol = @import("sokol");

const Options = struct {
    mod: *Build.Module,
    dep_sokol: *Build.Dependency,
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
    const dep_truetype = b.dependency("TrueType", .{
        .target = target,
        .optimize = optimize,
    });
    const dep_zigimg = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });

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
                .name = "TrueType",
                .module = dep_truetype.module("TrueType"),
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
    const opts = Options{ .mod = mod_root, .dep_sokol = dep_sokol };
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
