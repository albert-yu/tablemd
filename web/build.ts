import wgsl from "./bun-plugins/wgsl";
import { parseArgs } from "util";
import path from "path";

const currentDir = import.meta.dir;

const OUT_DIR = path.join(currentDir, "./build");
const CLIENT_SRC = path.join(currentDir, "./src/client");

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

const copyFileToBuild = (...pathToFile: string[]) => {
  const joined = path.join(...pathToFile);
  return Bun.write(
    path.join(OUT_DIR, joined),
    Bun.file(path.join(CLIENT_SRC, joined)),
  );
};

await Promise.all([copyFileToBuild("index.html")]);

Bun.build({
  entrypoints: [path.join(CLIENT_SRC, "main.ts")],
  outdir: OUT_DIR,
  minify: minify,
  sourcemap: sourcemap,
  plugins: [wgsl()],
});
