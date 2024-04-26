const { stat } = require("fs").promises;
const BASE_PATH = "./build";
Bun.serve({
  port: 8080,
  async fetch(req) {
    const filePath = BASE_PATH + new URL(req.url).pathname;
    return new Response(Bun.file(filePath));
  },
  error() {
    return new Response(null, { status: 404 });
  },
});
