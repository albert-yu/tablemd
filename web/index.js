try {
  /**
   * This gets assigned later
   * @type {WebAssembly.Memory}
   */
  let memory = undefined;
  // Set up the canvas with a 2D rendering context
  const canvas = document.querySelector("#canvas");
  const ctx = canvas.getContext("2d");
  const bcr = canvas.getBoundingClientRect();
  const BORDER_WIDTH = 1; // from CSS
  const width = bcr.width - BORDER_WIDTH * 2;
  const height = bcr.height - BORDER_WIDTH * 2;
  const size = width * height;
  // const byteSize = (2 * size) << 2;

  ctx.imageSmoothingEnabled = false;

  const response = await fetch("build/core.wasm");
  const bytes = await response.arrayBuffer();
  const result = await WebAssembly.instantiate(bytes, {
    env: {
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
  const initApp = exports.app_init;
  const deinitApp = exports.app_deinit;
  const app = initApp(width, height, 1);
  memory = exports.memory;
  const canvasBufferOffset = exports.get_canvas_buffer_ptr(app);
  const canvasData = new Uint32Array(memory.buffer, canvasBufferOffset, size);
  const imageData = ctx.createImageData(width, height);
  const argb = new Uint32Array(imageData.data.buffer);
  argb.set(canvasData);
  ctx.putImageData(imageData, 0, 0);

  deinitApp(app);
} catch (err) {
  console.log(err);
}
