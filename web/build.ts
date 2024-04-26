Bun.build({
  entrypoints: ['./src/client/index.ts'],
  outdir: './build',
  minify: true,
  sourcemap: 'inline',
});
