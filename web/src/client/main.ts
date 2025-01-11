import { type CanvasMode, CanvasEventHandler } from "./canvas-events";
import { UI } from "./ui";
import type { WASMApp, WASMExports } from "./wasm-types";

const cursorStyle = {
  select: "auto",
  pan: "grab",
} as const;

async function main() {
  // Start the WASM app
  let memory: WebAssembly.Memory;
  let app: WASMApp = 0;
  let exports: WASMExports;

  try {
    const response = await fetch("core.wasm");
    const bytes = await response.arrayBuffer();
    const result = await WebAssembly.instantiate(bytes, {
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
    exports = result.instance.exports as WASMExports;
    memory = exports.memory as WebAssembly.Memory;
    app = exports.app_init(100, 100, 1);
  } catch (err) {
    console.error(err);
    return;
  }

  // Set up the GPU
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

  let frames = 0;

  let time = Date.now();

  const fpsSpan = document.querySelector("#fps")!;

  // UI state
  const ui = new UI(device, context, format);
  await ui.init();

  function frame() {
    ui.render();
    frames++;
    const now = Date.now();
    if (now - time > 1000) {
      time = now;
      fpsSpan.innerHTML = `${frames}`;
      frames = 0;
    }
    ui.reset();
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
  canvasEvents.addListener({ event: "zoom", listener: zoomed });
  canvasEvents.addListener({
    event: "keydown",
    listener: (e) => {
      ui.handleKeyDown(e);
    },
  });
  canvasEvents.addListener({
    event: "click",
    listener: (p) => {
      ui.handleClick(p);
    },
  });
  canvasEvents.addListener({
    event: "hover",
    listener: (p) => {
      ui.handleHover(p);
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
    exports.app_set_canvas_size(app, canvas.clientWidth, canvas.clientHeight);
    ui.updateCanvasDimensions(canvas.clientWidth, canvas.clientHeight);
  });
}

function getCanvasSelectMode() {
  const checked = document.querySelector<HTMLInputElement>(
    'input[name="canvas-input-mode"]:checked',
  )?.value as CanvasMode | undefined;
  return checked;
}

await main();
