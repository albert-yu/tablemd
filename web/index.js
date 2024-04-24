if (!navigator.gpu) {
  throw new Error("WebGPU not supported on this browser.");
}

/**
 * @type {GPURequestAdapter}
 */
const adapter = await navigator.gpu.requestAdapter();
if (!adapter) {
  throw new Error("No adapter found.");
}

const getColorIndicesForCoord = (x, y, width) => {
  const red = y * (width * 4) + x * 4;
  return [red, red + 1, red + 2, red + 3];
};

const CANVAS_WIDTH = 500;
const CANVAS_HEIGHT = 500;

const device = await adapter.requestDevice();

/**
 * @type {WebGPUCanvasContext}
 */
const context = canvas.getContext("webgpu");

/**
 * @type {"rgba8unorm" | "bgra8unorm"}
 */
const canvasFormat = navigator.gpu.getPreferredCanvasFormat(adapter);

context.configure({
  device: device,
  format: canvasFormat,
});

try {
  /**
   * This gets assigned later
   * @type {WebAssembly.Memory}
   */
  let memory = undefined;
  // Set up the canvas with a 2D rendering context
  const canvas = document.querySelector("canvas");
  const ctx = canvas.getContext("2d");
  canvas.height = CANVAS_HEIGHT;
  canvas.width = CANVAS_WIDTH;
  const size = CANVAS_WIDTH * CANVAS_HEIGHT;
  const byteSize = size * 4;

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
  // const deinitApp = exports.app_deinit;
  const app = initApp(CANVAS_WIDTH, CANVAS_HEIGHT, 1);
  memory = exports.memory;

  const render = () => {
    const canvasBufferOffset = exports.get_canvas_buffer_ptr(app);
    const canvasData = new Uint8ClampedArray(
      memory.buffer,
      canvasBufferOffset,
      byteSize,
    );
    const imageData = new ImageData(canvasData, CANVAS_WIDTH);
    ctx.putImageData(imageData, 0, 0);
  };

  const handleClickCell = (e) => {
    const { offsetX, offsetY } = e;
    exports.app_highlight_clicked_cell(app, offsetX, offsetY);
    render();
  };
  const clearGrid = () => {
    exports.app_clear_grid(app);
    render();
  };
  canvas.addEventListener("click", handleClickCell);
  canvas.addEventListener("blur", clearGrid);
  render();

  // deinitApp(app);
} catch (err) {
  console.log(err);
}
