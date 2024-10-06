import { type CanvasMode, CanvasEventHandler } from "./canvas-events";
import { Vec2 } from "./Vec2";
import { Vec4 } from "./Vec4";
import { SAMPLE_COUNT } from "./constants";
import { UIRenderer } from "./ui-renderer";

type Interval = [number, number];

type ScaleDomainAndRange = {
  domain: Interval;
  range: Interval;
};

type Scales = {
  x: ScaleDomainAndRange;
  y: ScaleDomainAndRange;
};

const cursorStyle = {
  select: "auto",
  pan: "grab",
} as const;

async function main() {
  if (!navigator.gpu) {
    throw new Error("WebGPU not supported on this browser.");
  }

  const adapter = await navigator.gpu.requestAdapter();
  if (!adapter) {
    throw new Error("No adapter found.");
  }

  const CANVAS_WIDTH = 800;
  const CANVAS_HEIGHT = 800;

  const w = CANVAS_WIDTH;
  const h = CANVAS_HEIGHT;

  const device = await adapter.requestDevice();
  //
  const canvas = document.querySelector("canvas")!;
  const context = canvas.getContext("webgpu")!;

  const devicePixelRatio = window.devicePixelRatio;
  canvas.width = canvas.clientWidth * devicePixelRatio;
  canvas.height = canvas.clientHeight * devicePixelRatio;
  const format = navigator.gpu.getPreferredCanvasFormat();

  context.configure({
    device,
    format: format,
    // alphaMode: "premultiplied",
  });

  const N = 100;

  const data: [Float32Array, Float32Array] = [
    Float32Array.from({ length: N * N }).map((_, i) => (i % N) / N),
    Float32Array.from({ length: N * N }).map((_, j) => Math.floor(j / N) / N),
  ];

  const colorTexture = device.createTexture({
    label: "color",
    size: { width: canvas.width, height: canvas.height },
    sampleCount: SAMPLE_COUNT,
    format: "bgra8unorm",
    usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.COPY_SRC,
  });
  const colorTextureView = colorTexture.createView({ label: "color" });
  const ui = new UIRenderer(
    device,
    context,
    colorTextureView,
    data,
    CANVAS_WIDTH,
    CANVAS_HEIGHT,
  );

  function frame() {
    ui.rectangle({
      color: new Vec4(1, 0.5, 1, 1),
      position: new Vec2(400, 400),
      size: new Vec2(100, 100),
      corners: new Vec4(10, 10, 10, 10),
      sigma: 20,
    });
    ui.rectangle({
      color: new Vec4(0.5, 0.25, 0.5, 1),
      position: new Vec2(400, 400),
      size: new Vec2(100, 100),
      corners: new Vec4(10, 10, 10, 10),
      sigma: 0.25,
    });
    ui.rectangle({
      color: new Vec4(1, 0.5, 1, 1),
      position: new Vec2(401, 401),
      size: new Vec2(98, 98),
      corners: new Vec4(9, 9, 9, 9),
      sigma: 0.25,
    });

    ui.render();
    // requestAnimationFrame(frame);
  }

  requestAnimationFrame(frame);

  function zoomed({ k, x, y }: { k: number; x: number; y: number }) {
    // prettier-ignore
    let mat = [
      k, 0, 0, 0,
      0, k, 0, 0,
      0, 0, 1, 0,
      x, y, 0, 1,
    ];
    ui.updateZoom(mat);
    requestAnimationFrame(frame);
  }

  const DEFAULT_SCALE = 4;
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
      const gridX = (N * p.x) / w;
      const gridY = (N * p.y) / h;
      console.log({ x: gridX, y: gridY });

      // Suppose each spreadsheet cell is 2 grid cells wide by 1 cell tall.
      // Then, we'd have N / 2 columns and N rows.
      // TODO: We need to figure out which area was clicked
    },
  });
  (globalThis as any)["updateMode"] = function (radio: HTMLInputElement) {
    const value = radio.value as CanvasMode;
    zoom.mode = value;
    canvas.style.cursor = cursorStyle[value];
  };
  zoomed({ k: DEFAULT_SCALE, x: 0, y: 0 });

  try {
    let memory: WebAssembly.Memory | undefined = undefined;
    // const ctx = canvas.getContext("2d")!;
    // canvas.height = CANVAS_HEIGHT;
    // canvas.width = CANVAS_WIDTH;
    const size = CANVAS_WIDTH * CANVAS_HEIGHT;
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

function window_transform(scales: Scales, width: number, height: number) {
  // A function that creates the two matrices a webgl shader needs, in addition to the zoom state,
  // to stay aligned with canvas and d3 zoom.

  // width and height are svg parameters; x and y scales project from the data x and y into the
  // the webgl space.

  // Given two d3 scales in coordinate space, create two matrices that project from the original
  // space into [-1, 1] webgl space.

  // return the magnitude of a scale.
  const x_domain = scales.x.domain;
  const y_domain = scales.y.domain;
  const x_range = scales.x.range;
  const y_range = scales.y.range;
  let x_domain_mid = mean(x_domain);
  let y_domain_mid = mean(y_domain);
  const x_range_mid = mean(x_range);
  const y_range_mid = mean(y_range);
  let xmulti = gap(x_range) / gap(x_domain);
  let ymulti = gap(y_range) / gap(y_domain);

  // translates from data space to scaled space.
  // prettier-ignore
  const m1 = [
    xmulti, 0, 0, 0,
    0, ymulti, 0, 0,
    0, 0, 1, 0,
    -xmulti * x_domain_mid + x_range_mid,
    -ymulti * y_domain_mid + y_range_mid,
    0,
    1,
  ];

  // translate from scaled space to webgl space.
  // The '2' here is because webgl space runs from -1 to 1; the shift at the end is to
  // shift from [0, 2] to [-1, 1]
  // prettier-ignore
  const m2 = [
    2 / width, 0, 0, 0, // First column
    0, -2 / height, 0, 0, // Second column
    0, 0, 1, 0, // Third column (unchanged for z-axis in 2D transformations)
    -1, 1, 0, 1, // Fourth column, with translations adjusted for WebGL space
  ];

  return [m1, m2];
}

/**
 * Returns [min, max].
 *
 * Adapted from
 * https://github.com/d3/d3-array/blob/be0ae0d2b36ab91b833294ad2cfc5d5905acbd0f/src/extent.js#L1
 */
function extent(values: Float32Array): [number, number] {
  let min: number | undefined = undefined;
  let max: number | undefined = undefined;
  for (const value of values) {
    if (value != null) {
      if (min === undefined) {
        if (value >= value) {
          min = max = value;
        }
      } else {
        if (min > value) {
          min = value;
        }
        if (max! < value) {
          max = value;
        }
      }
    }
  }
  return [min!, max!];
}

function mean([low, hi]: Interval) {
  return (hi - low) / 2;
}

function gap(arr: Interval) {
  return arr[1] - arr[0];
}

function getCanvasSelectMode() {
  const checked = document.querySelector<HTMLInputElement>(
    'input[name="canvas-input-mode"]:checked',
  )?.value as CanvasMode | undefined;
  return checked;
}

await main();
