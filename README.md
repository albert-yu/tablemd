# spreadsheet

```sh
brew install zig
brew install wasmtime
zig build -Dtarget=wasm32-wasi
wasmtime zig-out/bin/spreadsheet.wasm
```
