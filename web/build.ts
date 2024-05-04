import wgsl from "./bun-plugins/wgsl";
import { parseArgs } from "util";
import path from "path";

const currentDir = import.meta.dir;

const OUT_DIR = path.join(currentDir, "./build");

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

await Bun.write(
  OUT_DIR + "/index.html",
  Bun.file(path.join(currentDir, "./src/client/index.html")),
);

Bun.build({
  entrypoints: [path.join(currentDir, "./src/client/main.ts")],
  outdir: OUT_DIR,
  minify: minify,
  sourcemap: sourcemap,
  plugins: [wgsl()],
});
