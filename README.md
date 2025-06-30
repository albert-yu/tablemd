# tablemd

A simple markdown table editor. Intended to be:

- Easy to use
- Fast startup time

## Development

Install [Zig](https://ziglang.org/download/).

Build and run.

```sh
# there's currently a bug in zig's wasm32-emscripten target
# where non-release builds complain about a missing base pointer
zig build -Dtarget=wasm32-emscripten --release=small run
```

Will automatically open a browser window with the app running.

## Deploy

TODO: add build script
