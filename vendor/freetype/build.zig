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
            const cache_result = initEmsdkCache(b, emsdk);
            lib.step.dependOn(cache_result.cache_init_step);
            lib.addIncludePath(cache_result.include_path);
        } else {
            @panic("Must provide emsdk dependency when building for web");
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
pub const EmsdkCacheResult = struct {
    cache_init_step: *Build.Step,
    include_path: Build.LazyPath,
};

/// Shared function to initialize Emscripten cache and get include path
/// TODO: Why do we need to do this on both the root build.zig and this one?
/// It seems like we only need to do this once.
pub fn initEmsdkCache(b: *Build, emsdk: *Build.Dependency) EmsdkCacheResult {
    // https://ziggit.dev/t/libc-not-linking-when-compiling-for-emscripten/5022/7
    const embuilder_path = emsdk.path(b.pathJoin(&.{ "upstream", "emscripten", "embuilder" }));

    // Use embuilder to ensure system libraries are built
    const cache_init = b.addSystemCommand(&.{
        embuilder_path.getPath(b),
        "build",
        "sysroot",
    });
    cache_init.has_side_effects = true;

    const include_path = emsdk.path(b.pathJoin(&.{ "upstream", "emscripten", "cache", "sysroot", "include" }));
    var dir = std.fs.openDirAbsolute(
        include_path.getPath(b),
        std.fs.Dir.OpenDirOptions{
            .access_sub_paths = true,
            .no_follow = true,
        },
    ) catch @panic("No emscripten cache. Generate it!");
    dir.close();

    return EmsdkCacheResult{
        .cache_init_step = &cache_init.step,
        .include_path = include_path,
    };
}

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
