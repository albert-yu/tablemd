import type { BunPlugin } from "bun";

const wgsl = (): BunPlugin => ({
  name: "WGSL loader",
  setup(build) {
    build.onLoad({ filter: /\.wgsl$/ }, async (args) => {
      const source = await Bun.file(args.path).text();
      const code = JSON.stringify(source);
      return {
        exports: { default: code },
        loader: "object",
      };
    });
  },
});

export default wgsl;
