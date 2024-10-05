# spreadsheet

Install [`zig >=0.13`](https://ziglang.org/learn/getting-started/#installing-zig).

Install [Bun](https://bun.sh), a fast all-in-one JavaScript runtime.

Build and run.

```sh
bun install
bun build-dev # build for development
bun dev # start the web server
```

`bun dev` just serves the files in the build output, so you could just

```sh
python3 -m http.server -d web/build 8080
```

Open `http://localhost:8080` in your browser.
