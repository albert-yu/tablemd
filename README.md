# spreadsheet

Install [`zig`](https://ziglang.org/learn/getting-started/#installing-zig) and [`wasmtime`](https://wasmtime.dev).

```sh
brew install zig
brew install wasmtime
```

Build and run.

```sh
cd core
zig build -Dtarget=wasm32-wasi
wasmtime zig-out/bin/spreadsheet.wasm
```
