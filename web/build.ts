import html from "bun-plugin-html";
import wgsl from "./bun-plugins/wgsl";
import { parseArgs } from "util";

const { values } = parseArgs({
  args: Bun.argv,
  options: {
    env: {
      type: "string",
    },
  },
  strict: true,
  allowPositionals: true,
});

const env = values.env || "development";

const minify = env === "production";
const sourcemap = env === "development" ? "inline" : "none";

Bun.build({
  entrypoints: ["./src/client/main.ts", "./src/client/index.html"],
  outdir: "./build",
  minify: minify,
  sourcemap: sourcemap,
  plugins: [html(), wgsl()],
});
