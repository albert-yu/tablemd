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
            lib.addSystemIncludePath(cache_result.include_path);
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
    const embuilder_path = emsdk.path(b.pathJoin(&.{ "upstream", "emscripten", "embuilder" }));
    const include_path = emsdk.path(b.pathJoin(&.{ "upstream", "emscripten", "cache", "sysroot", "include" }));

    // First step: wait for embuilder with timeout
    const wait_step = b.addSystemCommand(&.{
        "sh", "-c",
    });

    const wait_script = b.fmt(
        \\set -e
        \\echo "Waiting for embuilder to be available..."
        \\for i in {{1..30}}; do
        \\    if [ -x "{s}" ]; then
        \\        echo "Found embuilder after $i attempts"
        \\        exit 0
        \\    fi
        \\    echo "Waiting for embuilder... (attempt $i/30)"
        \\    sleep 2
        \\done
        \\echo "Error: embuilder not found after 30 attempts (60 seconds)"
        \\exit 1
    , .{embuilder_path.getPath(b)});

    wait_step.addArg(wait_script);
    wait_step.setName("wait_for_embuilder");

    // Second step: initialize cache
    const init_step = b.addSystemCommand(&.{ embuilder_path.getPath(b), "build", "libc" });
    init_step.step.dependOn(&wait_step.step);
    init_step.setName("init_emscripten_cache");

    // Third step: verify cache with timeout
    const verify_step = b.addSystemCommand(&.{
        "sh", "-c",
    });

    const verify_script = b.fmt(
        \\set -e
        \\echo "Verifying cache initialization..."
        \\for i in {{1..15}}; do
        \\    if [ -d "{s}" ] && [ "$(find "{s}" -type f | wc -l)" -gt 0 ]; then
        \\        echo "Cache verification successful after $i attempts"
        \\        exit 0
        \\    fi
        \\    echo "Waiting for cache files... (attempt $i/15)"
        \\    sleep 2
        \\done
        \\echo "Error: cache verification failed after 15 attempts (30 seconds)"
        \\exit 1
    , .{ include_path.getPath(b), include_path.getPath(b) });

    verify_step.addArg(verify_script);
    verify_step.step.dependOn(&init_step.step);
    verify_step.setName("verify_emscripten_cache");

    return EmsdkCacheResult{
        .cache_init_step = &verify_step.step,
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
