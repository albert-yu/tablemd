import wgsl from "./bun-plugins/wgsl";
import { parseArgs } from "util";
import path from "path";
import opentype from "opentype.js";

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

/**
 * Source: https://stackoverflow.com/a/61749783
 */
function refReplacer() {
  let m = new Map(),
    v = new Map(),
    init: any = null;

  return function (this: any, field: string, value: any) {
    let p = m.get(this) + (Array.isArray(this) ? `[${field}]` : "." + field);
    let isComplex = value === Object(value);

    if (isComplex) m.set(value, p);

    let pp = v.get(value) || "";
    let path = p.replace(/undefined\.\.?/, "");
    let val = pp ? `#REF:${pp[0] == "[" ? "$" : "$."}${pp}` : value;

    !init ? (init = value) : val === init ? (val = "#REF:$") : 0;
    if (!pp && isComplex) v.set(value, path);

    return val;
  };
}

const generateFontJSON = async () => {
  const ttfPath = path.join(CLIENT_SRC, "fonts/spacemono-regular.ttf");
  const raw = await Bun.file(ttfPath).arrayBuffer();
  const font = opentype.parse(raw);
  const str = JSON.stringify(font, refReplacer());
  const outPath = path.join(CLIENT_SRC, "fonts/gen/spacemono-regular.json");
  return await Bun.write(outPath, str);
};

await Promise.all([copyFileToBuild("index.html"), generateFontJSON()]);

Bun.build({
  entrypoints: [path.join(currentDir, "./src/client/main.ts")],
  outdir: OUT_DIR,
  minify: minify,
  sourcemap: sourcemap,
  plugins: [wgsl()],
});
