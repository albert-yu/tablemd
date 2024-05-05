import path from "path";
const currentDir = import.meta.dir;
const BASE_PATH = path.join(currentDir, "./build");

Bun.serve({
  port: 8080,
  async fetch(req) {
    const pathname = new URL(req.url).pathname;
    const file = pathname === "/" ? "/index.html" : pathname;
    const filePath = path.join(BASE_PATH, file);
    return new Response(Bun.file(filePath));
  },
  error() {
    return new Response(null, { status: 404 });
  },
});
