# tablemd

A simple markdown table editor. Intended to have:

- Frictionless user input
- Fast startup time

## Development

Install [Zig](https://ziglang.org/download/).

Build and run.

```sh
# there's currently a bug in zig's wasm32-emscripten target
# where non-release builds complain about a missing base pointer
zig build -Dtarget=wasm32-emscripten --release=safe run
```

Will automatically open a browser window with the app running.

### Mobile

To view the app on mobile, you'll need to get your IP address:

```sh
ifconfig en0 | awk '$1 == "inet" {print $2}'
```

Then, open `http://<IP_ADDRESS>:6931/root.html` in your mobile browser.

## Deploy

Run `./bundle.sh`. It'll output the static files to the `dist`
directory.
