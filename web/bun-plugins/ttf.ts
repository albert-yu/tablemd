import opentype from "opentype.js";
import type { BunPlugin } from "bun";

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

const ttf = (): BunPlugin => ({
  name: "TTF Font loader",
  async setup(build) {
    build.onLoad({ filter: /\.ttf$/ }, async (args) => {
      const source = await Bun.file(args.path).arrayBuffer();
      const font = opentype.parse(source);
      const str = JSON.stringify(font, refReplacer());
      return {
        contents: str,
        loader: "text",
      };
    });
  },
});

export default ttf;
