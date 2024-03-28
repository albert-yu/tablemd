# spreadsheet

Install [`zig >=0.12`](https://ziglang.org/learn/getting-started/#installing-zig).

Build and run.

```sh
./scripts/build-wasm.sh
cd web
python3 -m http.server
```

Open `http://localhost:8000` in your browser.

To run the REPL,

```sh
cd core
zig build run
```
