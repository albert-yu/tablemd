if (!navigator.gpu) {
  throw new Error("WebGPU not supported on this browser.");
}

const adapter = await navigator.gpu.requestAdapter();
if (!adapter) {
  throw new Error("No adapter found.");
}

// const getColorIndicesForCoord = (x, y, width) => {
//   const red = y * (width * 4) + x * 4;
//   return [red, red + 1, red + 2, red + 3];
// };

const CANVAS_WIDTH = 500;
const CANVAS_HEIGHT = 500;

const device = await adapter.requestDevice();

  // Set up the canvas with a 2D rendering context
const canvas = document.querySelector("canvas")!;
const context = canvas.getContext("webgpu")!;

const canvasFormat = navigator.gpu.getPreferredCanvasFormat();

context.configure({
  device: device,
  format: canvasFormat,
});

try {
  let memory: WebAssembly.Memory | undefined = undefined;
  const ctx = canvas.getContext("2d")!;
  canvas.height = CANVAS_HEIGHT;
  canvas.width = CANVAS_WIDTH;
  const size = CANVAS_WIDTH * CANVAS_HEIGHT;
  const _byteSize = size * 4;

  ctx.imageSmoothingEnabled = false;

  const response = await fetch("build/core.wasm");
  const bytes = await response.arrayBuffer();
  const _result = await WebAssembly.instantiate(bytes, {
    env: {
      print_u32: (x: number) => {
        console.log(x);
      },
      print: (ptr: number, len: number) => {
        const bytes = new Uint8Array(memory!.buffer, ptr, len);
        const str = new TextDecoder("utf-8").decode(bytes);
        console.log(str);
      },
    },
  });
  // const exports = result.instance.exports;
  // const initApp = exports.app_init as CallableFunction;
  // const getCanvasBufferPtr = exports.get_canvas_buffer_ptr as CallableFunction;
  // // const deinitApp = exports.app_deinit;
  // const app = initApp(CANVAS_WIDTH, CANVAS_HEIGHT, 1);
  // memory = exports.memory as WebAssembly.Memory;

  // const render = () => {
  //   const canvasBufferOffset = getCanvasBufferPtr(app);
  //   const canvasData = new Uint8ClampedArray(
  //     memory.buffer,
  //     canvasBufferOffset,
  //     byteSize,
  //   );
  //   const imageData = new ImageData(canvasData, CANVAS_WIDTH);
  //   ctx.putImageData(imageData, 0, 0);
  // };

  // const handleClickCell = (e) => {
  //   const { offsetX, offsetY } = e;
  //   exports.app_highlight_clicked_cell(app, offsetX, offsetY);
  //   render();
  // };
  // const clearGrid = () => {
  //   exports.app_clear_grid(app);
  //   render();
  // };
  // canvas.addEventListener("click", handleClickCell);
  // canvas.addEventListener("blur", clearGrid);
  // render();

  // deinitApp(app);
} catch (err) {
  console.log(err);
}
