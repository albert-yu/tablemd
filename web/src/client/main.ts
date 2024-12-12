import { vec2, vec4 } from "wgpu-matrix";
import { type CanvasMode, CanvasEventHandler } from "./canvas-events";
import { GRID_CELL_HEIGHT, GRID_CELL_WIDTH, UIRenderer } from "./ui-renderer";

const cursorStyle = {
  select: "auto",
  pan: "grab",
} as const;

async function main() {
  const canvas = document.querySelector("canvas")!;
  if (!navigator.gpu) {
    const errNode = document.createElement("div");
    errNode.innerHTML = `<p>WebGPU is not supported on this browser.</p>
    <p>Use Chrome, Edge, or another Chromium-based browser.</p>`;
    errNode.style.color = "red";
    canvas.replaceWith(errNode);
    console.error("WebGPU not supported on this browser.");
    return;
  }

  const adapter = await navigator.gpu.requestAdapter();
  if (!adapter) {
    throw new Error("No adapter found.");
  }

  const device = await adapter.requestDevice();
  const context = canvas.getContext("webgpu")!;
  const devicePixelRatio = window.devicePixelRatio;

  canvas.width = canvas.clientWidth * devicePixelRatio;
  canvas.height = canvas.clientHeight * devicePixelRatio;
  const format = navigator.gpu.getPreferredCanvasFormat();

  context.configure({
    device,
    format,
  });

  const w = () => canvas.clientWidth;
  const h = () => canvas.clientHeight;

  let frames = 0;

  let time = Date.now();

  const fpsSpan = document.querySelector("#fps")!;

  const position = vec2.create(GRID_CELL_WIDTH * 2, GRID_CELL_HEIGHT * 2);
  const ui = new UIRenderer(device, context, format);
  await ui.init();

  const str = "Hello, world!";
  ui.texts.push({ value: str, position });

  function frame() {
    ui.render();

    frames++;
    const now = Date.now();
    if (now - time > 1000) {
      time = now;
      fpsSpan.innerHTML = `${frames}`;
      frames = 0;
    }
    requestAnimationFrame(frame);
  }

  requestAnimationFrame(frame);

  function zoomed({ k, x, y }: { k: number; x: number; y: number }) {
    // prettier-ignore
    const mat = [
      k, 0, 0, 0,
      0, k, 0, 0,
      0, 0, 1, 0,
      x, y, 0, 1,
    ];
    ui.updateZoom(mat);
  }

  const DEFAULT_SCALE = 1;
  let mode: CanvasMode = getCanvasSelectMode() ?? "select";
  const canvasEvents = new CanvasEventHandler(canvas, {
    k: DEFAULT_SCALE,
    mode,
  });
  let hoverRectIndex: number | undefined = undefined;
  let activeRectIndex: number | undefined = undefined;
  const rectIndicesToTextIndices = new Map<number, number>();
  canvasEvents.addListener({ event: "zoom", listener: zoomed });
  canvasEvents.addListener({
    event: "keydown",
    listener: (e) => {
      let handled = true;
      switch (e.key) {
        case "Escape":
          activeRectIndex = undefined;
          break;
        // TODO: Implement
        case "ArrowUp":
          break;
        case "ArrowDown":
          break;
        case "ArrowLeft":
          break;
        case "ArrowRight":
          break;
        case "Delete":
          break;
        case "Backspace":
          break;
        default:
          handled = false;
          break;
      }

      if (handled) {
        return;
      }
      const isAlphaNumericOrSpace = e.key.match(/^[a-zA-Z0-9\s]$/);
      if (isAlphaNumericOrSpace) {
        const text = e.key;
        if (activeRectIndex && rectIndicesToTextIndices.has(activeRectIndex)) {
          const index = rectIndicesToTextIndices.get(activeRectIndex)!;
          ui.texts.update(index, {
            value: text,
          });
          return;
        }

        ui.texts.push({
          value: text,
          // TODO: get index of cell
          position: vec2.create(GRID_CELL_WIDTH * 2, GRID_CELL_HEIGHT * 3),
        });
      }
    },
  });
  canvasEvents.addListener({
    event: "click",
    listener: (p) => {
      // p is given relative to canvas dimensions.
      // Need to map it back to grid space (N x N)
      const cell = ui.getCell(p);

      const { x, y, w, h } = ui.getCellRect(cell);

      if (typeof activeRectIndex === "number") {
        ui.rects.update(activeRectIndex, {
          color: vec4.create(0, 1, 0, 1),
          position: vec2.create(x, y),
          size: vec2.create(w, h),
          corners: vec4.create(0, 0, 0, 0),
          sigma: 1e-6,
        });
      } else {
        const i = ui.rects.push({
          color: vec4.create(0, 1, 0, 1),
          position: vec2.create(x, y),
          size: vec2.create(w, h),
          corners: vec4.create(0, 0, 0, 0),
          sigma: 1e-6,
        });
        activeRectIndex = i;
      }
    },
  });
  canvasEvents.addListener({
    event: "hover",
    listener: (p) => {
      // p is given relative to canvas dimensions.
      // Need to map it back to grid space (N x N)
      const cell = ui.getCell(p);

      const { x, y, w, h } = ui.getCellRect(cell);

      if (typeof hoverRectIndex === "number") {
        ui.rects.update(hoverRectIndex, {
          color: vec4.create(1, 0, 0, 0.5), // semi-transparent red
          position: vec2.create(x, y),
          size: vec2.create(w, h),
          corners: vec4.create(0, 0, 0, 0),
          sigma: 1e-6,
        });
      } else {
        const i = ui.rects.push({
          color: vec4.create(1, 0, 0, 0.5), // semi-transparent red
          position: vec2.create(x, y),
          size: vec2.create(w, h),
          corners: vec4.create(0, 0, 0, 0),
          sigma: 1e-6,
        });
        hoverRectIndex = i;
      }
    },
  });
  (globalThis as any)["updateMode"] = function (radio: HTMLInputElement) {
    const value = radio.value as CanvasMode;
    canvasEvents.mode = value;
    canvas.style.cursor = cursorStyle[value];
  };
  zoomed({ k: DEFAULT_SCALE, x: 0, y: 0 });
  ui.updateCanvasDimensions(canvas.clientWidth, canvas.clientHeight);

  window.addEventListener("resize", () => {
    ui.updateCanvasDimensions(canvas.clientWidth, canvas.clientHeight);
  });

  try {
    let memory: WebAssembly.Memory | undefined = undefined;
    // const ctx = canvas.getContext("2d")!;
    // canvas.height = CANVAS_HEIGHT;
    // canvas.width = CANVAS_WIDTH;
    const size = w() * h();
    const _byteSize = size * 4;

    // ctx.imageSmoothingEnabled = false;

    const response = await fetch("core.wasm");
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
}

function getCanvasSelectMode() {
  const checked = document.querySelector<HTMLInputElement>(
    'input[name="canvas-input-mode"]:checked',
  )?.value as CanvasMode | undefined;
  return checked;
}

await main();
