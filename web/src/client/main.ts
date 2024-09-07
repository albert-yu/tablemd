import code from "./shaders/quad.wgsl";
const d3 = await import("d3");

async function main() {
  if (!navigator.gpu) {
    throw new Error("WebGPU not supported on this browser.");
  }

  const adapter = await navigator.gpu.requestAdapter();
  if (!adapter) {
    throw new Error("No adapter found.");
  }

  const CANVAS_WIDTH = 500;
  const CANVAS_HEIGHT = 500;

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

  const data = [
    Float32Array.from({ length: N * N }).map((_, i) => (i % N) / N),
    Float32Array.from({ length: N * N }).map((_, j) => Math.floor(j / N) / N),
  ];

  const square_box = Math.min(w, h);
  const d = { x: data[0], y: data[1] };
  const scales: Partial<Record<"x" | "y", any>> = {};
  for (const [name, dim] of [
    ["x", w],
    ["y", h],
  ] as const) {
    let buffer = (dim - square_box) / 2;
    scales[name] = d3
      .scaleLinear()
      .domain(d3.extent(d[name]) as [number, number])
      .range([buffer, dim - buffer]);
  }

  const [xbuf, ybuf] = data.map((arr) => {
    let buffer = device.createBuffer({
      size: arr.byteLength,
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
      mappedAtCreation: true,
    });
    new Float32Array(buffer.getMappedRange()).set(arr);
    buffer.unmap();
    return buffer;
  });

  const xyLayout = device.createBindGroupLayout({
    entries: [
      {
        binding: 0,
        visibility: GPUShaderStage.VERTEX,
        buffer: { type: "read-only-storage" },
      },
      {
        binding: 1,
        visibility: GPUShaderStage.VERTEX,
        buffer: { type: "read-only-storage" },
      },
    ],
  });

  const uniforms = new Float32Array(50);
  const uZoom = uniforms.subarray(0, 16);
  const uWindowScale = uniforms.subarray(16, 32);
  const uUntransform = uniforms.subarray(32, 48);
  const ubuffer = device.createBuffer({
    size: uniforms.byteLength,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  });

  {
    const mats = window_transform(scales.x, scales.y, w, h);
    uWindowScale.set(mats[0]);
    uUntransform.set(mats[1]);
  }

  let ulayout = device.createBindGroupLayout({
    entries: [
      {
        binding: 0,
        visibility: GPUShaderStage.VERTEX,
        buffer: { type: "uniform" },
      },
    ],
  });

  const module = device.createShaderModule({
    code: code,
  });

  const pipeline = device.createRenderPipeline({
    layout: device.createPipelineLayout({
      bindGroupLayouts: [xyLayout, ulayout],
    }),
    vertex: {
      module: module,
      entryPoint: "vert",
    },
    fragment: {
      module: module,
      targets: [
        {
          format: format,
          blend: {
            color: {
              srcFactor: "src-alpha",
              dstFactor: "one-minus-src-alpha",
              operation: "add",
            },
            alpha: {
              srcFactor: "src-alpha",
              dstFactor: "one-minus-src-alpha",
              operation: "add",
            },
          },
        },
      ],
    },
    primitive: {
      topology: "triangle-list",
    },
  });

  const xyGroup = device.createBindGroup({
    layout: xyLayout,
    entries: [
      { binding: 0, resource: { buffer: xbuf } },
      { binding: 1, resource: { buffer: ybuf } },
    ],
  });

  const uGroup = device.createBindGroup({
    layout: ulayout,
    entries: [{ binding: 0, resource: { buffer: ubuffer } }],
  });

  function frame() {
    const commandEncoder = device.createCommandEncoder();
    const textureView = context.getCurrentTexture().createView();
    const renderPassDescriptor: GPURenderPassDescriptor = {
      colorAttachments: [
        {
          view: textureView,
          clearValue: [1, 1, 1, 1],
          loadOp: "clear",
          storeOp: "store",
        },
      ],
    };
    const passEncoder = commandEncoder.beginRenderPass(renderPassDescriptor);
    passEncoder.setPipeline(pipeline);
    passEncoder.setBindGroup(0, xyGroup);
    passEncoder.setBindGroup(1, uGroup);
    passEncoder.draw(6, data[0].length);
    passEncoder.end();

    device.queue.submit([commandEncoder.finish()]);
    // requestAnimationFrame(frame);
  }

  requestAnimationFrame(frame);

  function zoomed({ k, x, y }: { k: number; x: number; y: number }) {
    let mat = [
      [k, 0, 0, 0],
      [0, k, 0, 0],
      [0, 0, 1, 0],
      [x, y, 0, 1],
    ];
    uZoom.set(mat.flat());
    device.queue.writeBuffer(ubuffer, 0, uniforms);
    requestAnimationFrame(frame);
  }

  const zoom = d3
    .zoom()
    .scaleExtent([0.1, 10000])
    .extent([
      [0, 0],
      [w, h],
    ])
    .on("zoom", (event) => zoomed(event.transform));

  // @ts-expect-error
  d3.select(context.canvas).call(zoom);
  zoomed(d3.zoomIdentity);

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

function window_transform(
  x_scale: any,
  y_scale: any,
  width: number,
  height: number
) {
  // A function that creates the two matrices a webgl shader needs, in addition to the zoom state,
  // to stay aligned with canvas and d3 zoom.

  // width and height are svg parameters; x and y scales project from the data x and y into the
  // the webgl space.

  // Given two d3 scales in coordinate space, create two matrices that project from the original
  // space into [-1, 1] webgl space.

  // return the magnitude of a scale.
  let gap = (arr: any) => arr[1] - arr[0];
  let x_mid = d3.mean(x_scale.domain())!;
  let y_mid = d3.mean(y_scale.domain())!;

  let xmulti = gap(x_scale.range()) / gap(x_scale.domain());
  let ymulti = gap(y_scale.range()) / gap(y_scale.domain());

  // translates from data space to scaled space.
  const m1 = [
    [xmulti, 0, 0, 0],
    [0, ymulti, 0, 0],
    [0, 0, 1, 0],
    [
      -xmulti * x_mid + d3.mean(x_scale.range())!,
      -ymulti * y_mid + d3.mean(y_scale.range())!,
      0,
      1,
    ],
  ];

  // translate from scaled space to webgl space.
  // The '2' here is because webgl space runs from -1 to 1; the shift at the end is to
  // shift from [0, 2] to [-1, 1]
  const m2 = [
    [2 / width, 0, 0, 0], // First column
    [0, -2 / height, 0, 0], // Second column
    [0, 0, 1, 0], // Third column (unchanged for z-axis in 2D transformations)
    [-1, 1, 0, 1], // Fourth column, with translations adjusted for WebGL space
  ];

  return [m1.flat(), m2.flat()];
}

await main();
