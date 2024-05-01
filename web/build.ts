import wgsl from "./bun-plugins/wgsl";
import { parseArgs } from "util";

const OUT_DIR = "./build";

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

await Bun.write(OUT_DIR + "/index.html", Bun.file("./src/client/index.html"));

Bun.build({
  entrypoints: ["./src/client/main.ts"],
  outdir: OUT_DIR,
  minify: minify,
  sourcemap: sourcemap,
  plugins: [wgsl()],
});
