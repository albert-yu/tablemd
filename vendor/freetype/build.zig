const std = @import("std");
const Build = std.Build;

pub fn build(b: *Build, options: BuildOptions) !*Build.Step.Compile {
    const target = options.target;
    const optimize = options.optimize;

    // Create FreeType static library
    const lib = b.addStaticLibrary(.{
        .name = "freetype",
        .target = target,
        .optimize = optimize,
    });

    // Add include directories
    lib.addIncludePath(b.path("vendor/freetype/include"));
    lib.addIncludePath(b.path("vendor/freetype/src"));

    // Common compilation flags
    var c_flags = std.ArrayList([]const u8).init(b.allocator);
    try c_flags.appendSlice(&.{
        "-DFT2_BUILD_LIBRARY",
        "-DFT_CONFIG_OPTION_ERROR_STRINGS",
        "-DFT_CONFIG_OPTION_NO_ASSEMBLER",
        "-DFT_CONFIG_OPTION_DISABLE_STREAM_SUPPORT",
        "-std=c99",
    });

    // For WASM builds, add Emscripten system include path
    if (target.result.cpu.arch.isWasm()) {
        if (options.emsdk) |emsdk| {
            // Force Emscripten cache population by running a simple emcc command
            const emcc_path = emsdk.path(b.pathJoin(&.{ "upstream", "emscripten", "emcc" }));
            const cache_init = b.addSystemCommand(&.{
                emcc_path.getPath(b),
                "--version",
            });
            cache_init.has_side_effects = true;

            const include_path = emsdk.path(b.pathJoin(&.{ "upstream", "emscripten", "cache", "sysroot", "include" }));
            std.log.info("WASM include path: {s}", .{include_path.getPath(b)});

            // Make library compilation depend on cache initialization
            lib.step.dependOn(&cache_init.step);
            lib.addSystemIncludePath(include_path);
        }
    }

    // Get FreeType source files
    const freetype_sources = getFreeTypeSources();

    // Add all FreeType C source files
    for (freetype_sources) |source| {
        lib.addCSourceFile(.{
            .file = b.path(source),
            .flags = c_flags.items,
        });
    }

    // For WASM builds, add setjmp/longjmp stub implementation
    if (target.result.cpu.arch.isWasm()) {
        lib.addCSourceFile(.{
            .file = b.path("vendor/freetype/setjmp_stub.c"),
            .flags = c_flags.items,
        });
    }

    lib.linkLibC();

    return lib;
}

pub const BuildOptions = struct {
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    emsdk: ?*Build.Dependency = null,
};

// Get FreeType source files
fn getFreeTypeSources() []const []const u8 {
    return &.{
        "vendor/freetype/src/base/ftbase.c",
        "vendor/freetype/src/base/ftinit.c",
        "vendor/freetype/src/base/ftsystem.c",
        "vendor/freetype/src/truetype/truetype.c",
        "vendor/freetype/src/sfnt/sfnt.c",
        "vendor/freetype/src/cff/cff.c",
        "vendor/freetype/src/type1/type1.c",
        "vendor/freetype/src/cid/type1cid.c",
        "vendor/freetype/src/pfr/pfr.c",
        "vendor/freetype/src/type42/type42.c",
        "vendor/freetype/src/winfonts/winfnt.c",
        "vendor/freetype/src/pcf/pcf.c",
        "vendor/freetype/src/bdf/bdf.c",
        "vendor/freetype/src/smooth/smooth.c",
        "vendor/freetype/src/raster/raster.c",
        "vendor/freetype/src/sdf/sdf.c",
        "vendor/freetype/src/svg/svg.c",
        "vendor/freetype/src/autofit/autofit.c",
        "vendor/freetype/src/pshinter/pshinter.c",
        "vendor/freetype/src/psaux/psaux.c",
        "vendor/freetype/src/psnames/psnames.c",
        "vendor/freetype/src/gzip/ftgzip.c",
        "vendor/freetype/src/lzw/ftlzw.c",
        "vendor/freetype/src/base/ftdebug.c",
        "vendor/freetype/src/base/ftbitmap.c",
        "vendor/freetype/src/base/ftglyph.c",
        "vendor/freetype/src/base/ftmm.c",
    };
}
