// Set up the canvas with a 2D rendering context
const canvas = document.querySelector("#canvas");
const ctx = canvas.getContext("2d");
const bcr = canvas.getBoundingClientRect();

const width = bcr.width;
const height = bcr.height;
const size = width * height;
const byteSize = (2 * size) << 2;

ctx.imageSmoothingEnabled = false;

// Compute the size of and instantiate the module's memory
const memory = new WebAssembly.Memory({
  initial: ((byteSize + 0xffff) & ~0xffff) >>> 16
});

try {
  const response = await fetch("build/core.wasm");
  const bytes = await response.arrayBuffer();
  const result = await WebAssembly.instantiate(bytes, {
    env: {
      memory,
      print: (ptr, len) => {
        const bytes = new Uint8Array(memory.buffer, ptr, len);
        const str = new TextDecoder("utf-8").decode(bytes);
        console.log(str);
      },
    },
  });
  const exports = result.instance.exports;
  const newSheet = exports.newSheet;
  const freeSheet = exports.freeSheet;
  const v = newSheet();
  console.log("v", v);
  // const memory = result.instance.exports.memory;
  freeSheet(v);
} catch (err) {
  console.log(err);
}
