# spreadsheet/core

This package is the main desktop app. It also includes the core logic
of the spreadsheet, including the parser, evaluator, and memory model.

To start the app, simply run `zig build run` from this directory.

To compile to WASM and WebGL, run `zig build run -Dtarget=wasm32-emscripten`.
This will also launch the app in the  default browser.

## Compiling shaders

There's a handy command line tool `sokol-shdc` that can be used
to compile a single .glsl shader into Metal, HLSL, GLSL, or WGSL.

You could build it from [source](https://github.com/floooh/sokol-tools), but it's easier to just download a binary
from the [sokol-tools-bin](https://github.com/floooh/sokol-tools-bin) repo.

Assuming you downloaded the repo to ~/Developer/sokol-tools-bin, to
compile `foo.glsl`, put it in `src/shaders/foo.glsl` and run:

```sh
~/Developer/sokol-tools-bin/bin/osx_arm64/sokol-shdc --input src/shaders/foo.glsl --output src/shaders/foo.glsl.zig -l glsl410:metal_macos:hlsl5:glsl300es:wgsl -f sokol_zig --reflection
```

By convention, the output file should be named `foo.glsl.zig` and
placed in the same directory as the input file.
