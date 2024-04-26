import html from 'bun-plugin-html';
Bun.build({
  entrypoints: ['./src/client/main.ts', "./src/client/index.html"],
  outdir: './build',
  minify: true,
  sourcemap: 'inline',
  plugins:[html()],
});
