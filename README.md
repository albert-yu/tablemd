# spreadsheet

Install [Bun](https://bun.sh), a fast all-in-one JavaScript runtime.

Build and run.

```sh
bun install
cd web && bun dev # start the web server and listen for changes
```

Open `http://localhost:3000` in your browser.

## Deploy

```sh
bun build-prod # build the WASM and web app production mode
```

Build results are in `web/build`.
