const std = @import("std");
const sokol = @import("sokol");

fn addUnitTest(b: *std.Build, options: std.Build.TestOptions) *std.Build.Step.Run {
    const unit_test = b.addTest(options);
    const run_unit_tests = b.addRunArtifact(unit_test);
    return run_unit_tests;
}

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const dep_sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });
    // special case handling for native vs web build
    if (target.result.isWasiLibC()) {
        try buildWeb(b, target, optimize, dep_sokol);
    } else {
        try buildNative(b, target, optimize, dep_sokol);
    }

    const run_lexer_tests = addUnitTest(b, .{
        .root_source_file = b.path("src/lexer.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_parser_tests = addUnitTest(b, .{
        .root_source_file = b.path("src/parser.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_engine_tests = addUnitTest(b, .{
        .root_source_file = b.path("src/engine.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_map_tests = addUnitTest(b, .{
        .root_source_file = b.path("src/map.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lexer_tests.step);
    test_step.dependOn(&run_parser_tests.step);
    test_step.dependOn(&run_engine_tests.step);
    test_step.dependOn(&run_map_tests.step);
}

// this is the regular build for all native platforms, nothing surprising here
fn buildNative(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, dep_sokol: *std.Build.Dependency) !void {
    const app = b.addExecutable(.{
        .name = "app",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
    });
    app.root_module.addImport("sokol", dep_sokol.module("sokol"));
    app.addIncludePath(b.path("vendor"));
    b.installArtifact(app);
    const run = b.addRunArtifact(app);
    b.step("run", "Run app").dependOn(&run.step);
}

// for web builds, the Zig code needs to be built into a library and linked with the Emscripten linker
fn buildWeb(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, dep_sokol: *std.Build.Dependency) !void {
    const lib = b.addStaticLibrary(.{
        .name = "app",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
    });
    lib.root_module.addImport("sokol", dep_sokol.module("sokol"));
    lib.addIncludePath(b.path("vendor"));

    // create a build step which invokes the Emscripten linker
    const emsdk = dep_sokol.builder.dependency("emsdk", .{});
    const link_step = try sokol.emLinkStep(b, .{
        .lib_main = lib,
        .target = target,
        .optimize = optimize,
        .emsdk = emsdk,
        .use_webgl2 = true,
        .use_emmalloc = true,
        .use_filesystem = false,
        .shell_file_path = dep_sokol.path("src/sokol/web/shell.html"),
    });
    // ...and a special run step to start the web build output via 'emrun'
    const run = sokol.emRunStep(b, .{ .name = "app", .emsdk = emsdk });
    run.step.dependOn(&link_step.step);
    b.step("run", "Run app").dependOn(&run.step);
}
