try {
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
    initial: ((byteSize + 0xffff) & ~0xffff) >>> 16,
  });

  const response = await fetch("build/core.wasm");
  const bytes = await response.arrayBuffer();
  const result = await WebAssembly.instantiate(bytes, {
    env: {
      memory: memory,
      print_u32: (x) => {
        console.log(x);
      },
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
  exports.init(width, height);

  var mem = new Uint32Array(memory.buffer);

  // Update about 30 times a second
  (function update() {
    setTimeout(update, 1000 / 30);
    mem.copyWithin(0, size, 2 * size); // copy output to input
    // exports.step(); // perform the next step
  })();

  // Keep rendering the output at [size, 2*size]
  var imageData = ctx.createImageData(width, height);
  var argb = new Uint32Array(imageData.data.buffer);

  (function render() {
    requestAnimationFrame(render);
    argb.set(mem.subarray(size, 2 * size)); // copy output to image buffer
    ctx.putImageData(imageData, 0, 0); // apply image buffer
  })();

  freeSheet(v);
} catch (err) {
  console.log(err);
}
