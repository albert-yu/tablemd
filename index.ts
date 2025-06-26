import path from "path";
const currentDir = import.meta.dir;
const BASE_PATH = path.join(currentDir, "./build");

const PORT = 3000;
console.log(`Listening on port ${PORT}`);
Bun.serve({
  port: PORT,
  async fetch(req) {
    const pathname = new URL(req.url).pathname;
    const file = pathname === "/" ? "/index.html" : pathname;
    console.log(`GET ${file}`);
    const filePath = path.join(BASE_PATH, file);
    return new Response(Bun.file(filePath));
  },
  error(req) {
    console.error(req.message);
    return new Response(null, { status: 404 });
  },
});
