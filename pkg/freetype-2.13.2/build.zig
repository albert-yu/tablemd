const std = @import("std");
const builtin = @import("builtin");
const Build = std.Build;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("freetype", .{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const lib = b.addLibrary(.{
        .name = "freetype",
        .root_module = mod,
    });
    const emsdk = b.dependency("emsdk", .{});

    // Add include directories
    lib.addIncludePath(b.path("include"));
    lib.addIncludePath(b.path("src"));

    const is_wasm = target.result.cpu.arch.isWasm();

    // WASM-specific configuration
    if (is_wasm) {
        // Set up emsdk for WASM compilation
        if (emSdkSetupStep(b, emsdk)) |emsdk_setup| {
            lib.step.dependOn(&emsdk_setup.step);
        }

        // Set emscripten-specific macros
        lib.root_module.addCMacro("__EMSCRIPTEN__", "1");

        // Use custom config directory for WASM
        lib.addIncludePath(b.path("include/freetype/config/wasm"));
    }

    // Define FreeType configuration macros
    lib.root_module.addCMacro("FT2_BUILD_LIBRARY", "");

    // Native-specific configuration
    if (!is_wasm) {
        lib.root_module.addCMacro("FT_CONFIG_OPTION_SYSTEM_ZLIB", "");
    }

    // Core base files
    lib.addCSourceFile(.{ .file = b.path("src/base/ftbase.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/base/ftinit.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/base/ftsystem.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/base/ftdebug.c"), .flags = &.{} });

    // Font drivers
    lib.addCSourceFile(.{ .file = b.path("src/truetype/truetype.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/type1/type1.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/cff/cff.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/cid/type1cid.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/pfr/pfr.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/type42/type42.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/winfonts/winfnt.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/pcf/pcf.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/bdf/bdf.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/sfnt/sfnt.c"), .flags = &.{} });

    // Hinting modules
    lib.addCSourceFile(.{ .file = b.path("src/autofit/autofit.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/pshinter/pshinter.c"), .flags = &.{} });

    // Raster modules
    lib.addCSourceFile(.{ .file = b.path("src/smooth/smooth.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/raster/raster.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/sdf/sdf.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/svg/svg.c"), .flags = &.{} });

    // Auxiliary modules
    lib.addCSourceFile(.{ .file = b.path("src/cache/ftcache.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/psaux/psaux.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/psnames/psnames.c"), .flags = &.{} });

    // Only add compression modules for native builds
    if (!target.result.cpu.arch.isWasm()) {
        lib.addCSourceFile(.{ .file = b.path("src/gzip/ftgzip.c"), .flags = &.{} });
        lib.addCSourceFile(.{ .file = b.path("src/lzw/ftlzw.c"), .flags = &.{} });
        lib.addCSourceFile(.{ .file = b.path("src/bzip2/ftbzip2.c"), .flags = &.{} });
    }

    // Base extensions
    lib.addCSourceFile(.{ .file = b.path("src/base/ftbbox.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/base/ftbdf.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/base/ftbitmap.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/base/ftcid.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/base/ftfstype.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/base/ftgasp.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/base/ftglyph.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/base/ftgxval.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/base/ftmm.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/base/ftotval.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/base/ftpatent.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/base/ftpfr.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/base/ftstroke.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/base/ftsynth.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/base/fttype1.c"), .flags = &.{} });
    lib.addCSourceFile(.{ .file = b.path("src/base/ftwinfnt.c"), .flags = &.{} });

    // Link system libraries
    lib.linkLibC();

    // For native builds, link with system zlib
    if (!target.result.cpu.arch.isWasm()) {
        lib.linkSystemLibrary("z");
    }

    b.installArtifact(lib);

    // Create a module for easier import
    const freetype_module = b.addModule("freetype", .{
        .root_source_file = b.path("freetype.zig"),
        .target = target,
        .optimize = optimize,
    });
    freetype_module.linkLibrary(lib);
    freetype_module.addIncludePath(b.path("include"));
}

fn emSdkSetupStep(b: *Build, emsdk: *Build.Dependency) ?*Build.Step.Run {
    const dot_emsc_path = emSdkLazyPath(b, emsdk, &.{".emscripten"}).getPath(b);
    const dot_emsc_exists = !std.meta.isError(std.fs.accessAbsolute(dot_emsc_path, .{}));
    if (!dot_emsc_exists) {
        const emsdk_install = createEmsdkStep(b, emsdk);
        emsdk_install.addArgs(&.{ "install", "latest" });
        const emsdk_activate = createEmsdkStep(b, emsdk);
        emsdk_activate.addArgs(&.{ "activate", "latest" });
        emsdk_activate.step.dependOn(&emsdk_install.step);
        return emsdk_activate;
    } else {
        return null;
    }
}

// helper function to build a LazyPath from the emsdk root and provided path components
fn emSdkLazyPath(b: *Build, emsdk: *Build.Dependency, sub_paths: []const []const u8) Build.LazyPath {
    return emsdk.path(b.pathJoin(sub_paths));
}

fn createEmsdkStep(b: *Build, emsdk: *Build.Dependency) *Build.Step.Run {
    if (builtin.os.tag == .windows) {
        return b.addSystemCommand(&.{emSdkLazyPath(b, emsdk, &.{"emsdk.bat"}).getPath(b)});
    } else {
        const step = b.addSystemCommand(&.{"bash"});
        step.addArg(emSdkLazyPath(b, emsdk, &.{"emsdk"}).getPath(b));
        return step;
    }
}
