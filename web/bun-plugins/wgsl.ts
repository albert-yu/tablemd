import type { BunPlugin } from "bun";

const wgsl = (): BunPlugin => ({
  name: "WGSL loader",
  async setup(build) {
    build.onLoad({ filter: /\.wgsl$/ }, async (args) => {
      const source = await Bun.file(args.path).text();
      return {
        contents: source,
        loader: "text",
      };
    });
  },
});

export default wgsl;
