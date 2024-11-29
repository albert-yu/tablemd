import { vec2, vec4 } from "wgpu-matrix";
import { type CanvasMode, CanvasEventHandler } from "./canvas-events";
import { getRectCorners, UIRenderer } from "./ui-renderer";

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

  const SCALE = 0.001;
  const position = vec2.create(0.25, 0.25);
  const ui = new UIRenderer(device, context, format);
  await ui.init();

  // const str = "Hello, world!";
  // ui.pushText({ value: str });
  ui.rectangle({
    color: vec4.create(1, 0.5, 1, 1),
    position: position,
    size: vec2.scale(vec2.create(100, 100), SCALE),
    corners: vec4.scale(vec4.create(10, 10, 10, 10), SCALE),
    sigma: 0.01,
  });
  ui.rectangle({
    color: vec4.create(0.5, 0.25, 0.5, 1),
    position: position,
    size: vec2.scale(vec2.create(100, 100), SCALE),
    corners: vec4.scale(vec4.create(10, 10, 10, 10), SCALE),
    sigma: SCALE * 0.01,
  });
  ui.rectangle({
    color: vec4.create(1, 0.5, 1, 1),
    position: vec2.add(position, vec2.create(SCALE, SCALE)),
    size: vec2.scale(vec2.create(98, 98), SCALE),
    corners: vec4.scale(vec4.create(9, 9, 9, 9), SCALE),
    sigma: SCALE * 0.01,
  });

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
  const zoom = new CanvasEventHandler(canvas, {
    k: DEFAULT_SCALE,
    mode,
  });
  zoom.addListener({ event: "zoom", listener: zoomed });
  zoom.addListener({
    event: "click",
    listener: (p) => {
      // p is given relative to canvas dimensions.
      // Need to map it back to grid space (N x N)
      const cell = ui.getClickedCell(p);
      console.log(cell);

      const CELL_W = 1;
      // Round to nearest grid point
      // Convert to cell coordinates
      // console.log({
      //   clickedPoint: p,
      //   gridCoords: { x: gridX, y: gridY },
      //   cell: { x: cellX, y: cellY },
      // });
      // const { tl: tl0, tr: tr0, bl: bl0 } = getRectCorners(cellX, cellY);
      // console.log(tl0);
      // const tr = zoom.invert(tr0);
      // const tl = zoom.invert(tl0);
      // const bl = zoom.invert(bl0);
      const { tl, tr, bl } = getRectCorners(cell.x, cell.y);
      const cellWidth = (tr.x - tl.x) * CELL_W;
      const cellHeight = bl.y - tl.y;

      ui.rectangle({
        color: vec4.create(1, 0, 0, 0.5), // semi-transparent red
        position: vec2.create(tl.x, tl.y),
        size: vec2.create(cellWidth, cellHeight),
        corners: vec4.create(0, 0, 0, 0),
        sigma: 1e-6,
      });
    },
  });
  (globalThis as any)["updateMode"] = function (radio: HTMLInputElement) {
    const value = radio.value as CanvasMode;
    zoom.mode = value;
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
