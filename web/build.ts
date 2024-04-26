const file = Bun.file("./src/client/index.html");
Bun.write("./build/index.html", file);
Bun.build({
  entrypoints: ['./src/client/main.ts'],
  outdir: './build',
  minify: true,
  sourcemap: 'inline',
});
