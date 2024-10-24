import { type CanvasMode, CanvasEventHandler } from "./canvas-events";
import { Vec2 } from "./Vec2";
import { Vec4 } from "./Vec4";
import { GRID_N as N } from "./constants";
import { UIRenderer } from "./ui-renderer";
import { spaceMonoFontAtlas } from "./fonts/space-mono-regular-msdf/space-mono-regular";
import spaceMonoFontJSON from "./fonts/space-mono-regular-msdf/space-mono-regular-msdf.json";
import {
  MsdfFont,
  type Kerning,
  type KerningMap,
  type MsdfChar,
} from "./msdf-font";
import msdfTextWGSL from "./shaders/msdf-text.wgsl";
import { MsdfText, type MsdfTextMeasurements } from "./msdf-text";
import { mat4, vec3, type Mat4 } from "wgpu-matrix";

interface MsdfTextFormattingOptions {
  centered?: boolean;
  pixelScale?: number;
  color?: [number, number, number, number];
}

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

  // Font atlas
  const imageBitmap = await createImageBitmap(new Blob([spaceMonoFontAtlas]));

  const texture = device.createTexture({
    label: "MSDF font atlas texture Space Mono",
    size: [imageBitmap.width, imageBitmap.height, 1],
    format: "rgba8unorm",
    usage:
      GPUTextureUsage.TEXTURE_BINDING |
      GPUTextureUsage.COPY_DST |
      GPUTextureUsage.RENDER_ATTACHMENT,
  });
  device.queue.copyExternalImageToTexture(
    { source: imageBitmap },
    { texture },
    [imageBitmap.width, imageBitmap.height],
  );
  const charCount = spaceMonoFontJSON.chars.length;

  const charsBuffer = device.createBuffer({
    label: "MSDF character layout buffer",
    size: charCount * Float32Array.BYTES_PER_ELEMENT * 8,
    usage: GPUBufferUsage.STORAGE,
    mappedAtCreation: true,
  });
  const charsArray = new Float32Array(charsBuffer.getMappedRange());
  const u = 1 / spaceMonoFontJSON.common.scaleW;
  const v = 1 / spaceMonoFontJSON.common.scaleH;

  const ui = new UIRenderer(device, context, format);
  const chars: { [x: number]: MsdfChar } = {};

  let offset = 0;
  for (const [i, char] of spaceMonoFontJSON.chars.entries()) {
    // @ts-expect-error charIndex assigned in following line
    chars[char.id] = char;
    chars[char.id].charIndex = i;
    charsArray[offset] = char.x * u; // texOffset.x
    charsArray[offset + 1] = char.y * v; // texOffset.y
    charsArray[offset + 2] = char.width * u; // texExtent.x
    charsArray[offset + 3] = char.height * v; // texExtent.y
    charsArray[offset + 4] = char.width; // size.x
    charsArray[offset + 5] = char.height; // size.y
    charsArray[offset + 6] = char.xoffset; // offset.x
    charsArray[offset + 7] = -char.yoffset; // offset.y
    offset += 8;
  }

  charsBuffer.unmap();

  const sampler = device.createSampler({
    label: "MSDF text sampler",
    minFilter: "linear",
    magFilter: "linear",
    mipmapFilter: "linear",
    maxAnisotropy: 16,
  });
  const fontBindGroupLayout = device.createBindGroupLayout({
    label: "MSDF font group layout",
    entries: [
      {
        binding: 0,
        visibility: GPUShaderStage.FRAGMENT,
        texture: {},
      },
      {
        binding: 1,
        visibility: GPUShaderStage.FRAGMENT,
        sampler: {},
      },
      {
        binding: 2,
        visibility: GPUShaderStage.VERTEX,
        buffer: { type: "read-only-storage" },
      },
    ],
  });

  const bindGroup = device.createBindGroup({
    label: "msdf font bind group",
    layout: fontBindGroupLayout,
    entries: [
      {
        binding: 0,
        // TODO: Allow multi-page fonts
        resource: texture.createView(),
      },
      {
        binding: 1,
        resource: sampler,
      },
      {
        binding: 2,
        resource: { buffer: charsBuffer },
      },
    ],
  });

  const kernings: KerningMap = new Map();

  if (spaceMonoFontJSON.kernings) {
    // Our particular font is monospaced, so we can actually remove this
    for (const kerning of spaceMonoFontJSON.kernings as Kerning[]) {
      let charKerning = kernings.get(kerning.first);
      if (!charKerning) {
        charKerning = new Map<number, number>();
        kernings.set(kerning.first, charKerning);
      }
      charKerning.set(kerning.second, kerning.amount);
    }
  }
  const shaderModule = device.createShaderModule({
    label: "MSDF text shader",
    code: msdfTextWGSL,
  });

  const textBindGroupLayout = device.createBindGroupLayout({
    label: "MSDF text group layout",
    entries: [
      {
        binding: 0,
        visibility: GPUShaderStage.VERTEX,
        buffer: {},
      },
      {
        binding: 1,
        visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT,
        buffer: { type: "read-only-storage" },
      },
    ],
  });

  const depthFormat = "depth24plus";

  const fontPipeline = device.createRenderPipeline({
    label: `msdf text pipeline`,
    layout: device.createPipelineLayout({
      bindGroupLayouts: [fontBindGroupLayout, textBindGroupLayout],
    }),
    vertex: {
      module: shaderModule,
      entryPoint: "vertexMain",
    },
    fragment: {
      module: shaderModule,
      entryPoint: "fragmentMain",
      targets: [
        {
          format: format,
          blend: {
            color: {
              srcFactor: "src-alpha",
              dstFactor: "one-minus-src-alpha",
            },
            alpha: {
              srcFactor: "one",
              dstFactor: "one",
            },
          },
        },
      ],
    },
    primitive: {
      topology: "triangle-strip",
      stripIndexFormat: "uint32",
    },
    depthStencil: {
      depthWriteEnabled: false,
      depthCompare: "less",
      format: depthFormat,
    },
  });

  const font = new MsdfFont(
    fontPipeline,
    bindGroup,
    spaceMonoFontJSON.common.lineHeight,
    chars,
    kernings,
  );

  const cameraArray = new Float32Array(16 * 2);

  const cameraUniformBuffer = device.createBuffer({
    label: "MSDF camera uniform buffer",
    size: cameraArray.byteLength,
    usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.UNIFORM,
  });

  const renderBundleDescriptor: GPURenderBundleEncoderDescriptor = {
    colorFormats: [format],
    depthStencilFormat: depthFormat,
  };

  const formatText = (
    font: MsdfFont,
    text: string,
    options: MsdfTextFormattingOptions = {},
  ) => {
    const textBuffer = device.createBuffer({
      label: "msdf text buffer",
      size: (text.length + 6) * Float32Array.BYTES_PER_ELEMENT * 4,
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
      mappedAtCreation: true,
    });

    const textArray = new Float32Array(textBuffer.getMappedRange());
    let offset = 24; // Accounts for the values managed by MsdfText internally.

    let measurements: MsdfTextMeasurements;
    if (options.centered) {
      measurements = measureText(font, text);

      measureText(
        font,
        text,
        (textX: number, textY: number, line: number, char: MsdfChar) => {
          const lineOffset =
            measurements.width * -0.5 -
            (measurements.width - measurements.lineWidths[line]) * -0.5;

          textArray[offset] = textX + lineOffset;
          textArray[offset + 1] = textY + measurements.height * 0.5;
          textArray[offset + 2] = char.charIndex;
          offset += 4;
        },
      );
    } else {
      measurements = measureText(
        font,
        text,
        (textX: number, textY: number, line: number, char: MsdfChar) => {
          textArray[offset] = textX;
          textArray[offset + 1] = textY;
          textArray[offset + 2] = char.charIndex;
          offset += 4;
        },
      );
    }

    textBuffer.unmap();

    const bindGroup = device.createBindGroup({
      label: "msdf text bind group",
      layout: textBindGroupLayout,
      entries: [
        {
          binding: 0,
          resource: { buffer: cameraUniformBuffer },
        },
        {
          binding: 1,
          resource: { buffer: textBuffer },
        },
      ],
    });

    const encoder = device.createRenderBundleEncoder(renderBundleDescriptor);
    encoder.setPipeline(font.pipeline);
    encoder.setBindGroup(0, font.bindGroup);
    encoder.setBindGroup(1, bindGroup);
    encoder.draw(4, measurements.printedCharCount);
    const renderBundle = encoder.finish();

    const msdfText = new MsdfText(
      device,
      renderBundle,
      measurements,
      font,
      textBuffer,
    );
    if (options.pixelScale !== undefined) {
      msdfText.setPixelScale(options.pixelScale);
    }

    if (options.color !== undefined) {
      msdfText.setColor(...options.color);
    }

    return msdfText;
  };

  const largeText = formatText(
    font,
    `
WebGPU exposes an API for performing operations, such as rendering
and computation, on a Graphics Processing Unit.

Graphics Processing Units, or GPUs for short, have been essential
in enabling rich rendering and computational applications in personal
computing. WebGPU is an API that exposes the capabilities of GPU
hardware for the Web. The API is designed from the ground up to
efficiently map to (post-2014) native GPU APIs. WebGPU is not related
to WebGL and does not explicitly target OpenGL ES.

WebGPU sees physical GPU hardware as GPUAdapters. It provides a
connection to an adapter via GPUDevice, which manages resources, and
the device's GPUQueues, which execute commands. GPUDevice may have
its own memory with high-speed access to the processing units.
GPUBuffer and GPUTexture are the physical resources backed by GPU
memory. GPUCommandBuffer and GPURenderBundle are containers for
user-recorded commands. GPUShaderModule contains shader code. The
other resources, such as GPUSampler or GPUBindGroup, configure the
way physical resources are used by the GPU.

GPUs execute commands encoded in GPUCommandBuffers by feeding data
through a pipeline, which is a mix of fixed-function and programmable
stages. Programmable stages execute shaders, which are special
programs designed to run on GPU hardware. Most of the state of a
pipeline is defined by a GPURenderPipeline or a GPUComputePipeline
object. The state not included in these pipeline objects is set
during encoding with commands, such as beginRenderPass() or
setBlendConstant().`,
    { pixelScale: 1 / 256 },
  );

  const aspect = canvas.width / canvas.height;
  const projectionMatrix = mat4.perspective(
    (2 * Math.PI) / 5,
    aspect,
    1,
    100.0,
  );
  const modelViewProjectionMatrix = mat4.create();

  const updateCamera = (projection: Mat4, view: Mat4) => {
    cameraArray.set(projection, 0);
    cameraArray.set(view, 16);
    device.queue.writeBuffer(cameraUniformBuffer, 0, cameraArray);
  };

  // const start = Date.now();

  function getTransformationMatrix() {
    const viewMatrix = mat4.identity();
    mat4.translate(viewMatrix, vec3.fromValues(0, 0, -5), viewMatrix);

    // Update the projection and view matrices for the text
    updateCamera(projectionMatrix, viewMatrix);

    // Update the transform of all the text surrounding the cube
    const textMatrix = mat4.create();

    // Update the transform of the larger block of text
    // const crawl = ((Date.now() - start) / 2500) % 14;
    mat4.identity(textMatrix);
    mat4.translate(textMatrix, [-3, 7 - 3.01, 0], textMatrix);
    largeText.setTransform(textMatrix);

    return modelViewProjectionMatrix;
  }

  const uniformBufferSize = 4 * 16; // 4x4 matrix
  const uniformBuffer = device.createBuffer({
    size: uniformBufferSize,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  });
  const depthTexture = device.createTexture({
    size: [canvas.width, canvas.height],
    format: depthFormat,
    usage: GPUTextureUsage.RENDER_ATTACHMENT,
  });
  const renderPassDescriptor: GPURenderPassDescriptor = {
    // @ts-expect-error
    colorAttachments: [
      {
        view: undefined, // Assigned later

        clearValue: [0, 0, 0, 1],
        loadOp: "clear",
        storeOp: "store",
      },
    ],
    depthStencilAttachment: {
      view: depthTexture.createView(),

      depthClearValue: 1.0,
      depthLoadOp: "clear",
      depthStoreOp: "store",
    },
  };

  let frames = 0;

  let time = Date.now();

  const fpsSpan = document.querySelector("#fps")!;

  const SCALE = 0.001;
  const position = new Vec2(0.25, 0.25);
  const transformationMatrix = getTransformationMatrix();
  device.queue.writeBuffer(
    uniformBuffer,
    0,
    transformationMatrix.buffer,
    transformationMatrix.byteOffset,
    transformationMatrix.byteLength,
  );
  function frame() {
    // @ts-expect-error
    renderPassDescriptor.colorAttachments[0].view = context
      .getCurrentTexture()
      .createView();

    const commandEncoder = device.createCommandEncoder();
    const passEncoder = commandEncoder.beginRenderPass(renderPassDescriptor);
    // passEncoder.setPipeline(pipeline);
    // passEncoder.setBindGroup(0, uniformBindGroup);

    const renderBundle = largeText.getRenderBundle();
    passEncoder.executeBundles([renderBundle]);

    // ui.rectangle({
    //   color: new Vec4(1, 0.5, 1, 1),
    //   position: position,
    //   size: new Vec2(100, 100).scale(SCALE),
    //   corners: new Vec4(10, 10, 10, 10).scale(SCALE),
    //   sigma: 0.01,
    // });
    // ui.rectangle({
    //   color: new Vec4(0.5, 0.25, 0.5, 1),
    //   position: position,
    //   size: new Vec2(100, 100).scale(SCALE),
    //   corners: new Vec4(10, 10, 10, 10).scale(SCALE),
    //   sigma: SCALE * 0.01,
    // });
    // ui.rectangle({
    //   color: new Vec4(1, 0.5, 1, 1),
    //   position: position.add(new Vec2(SCALE, SCALE)),
    //   size: new Vec2(98, 98).scale(SCALE),
    //   corners: new Vec4(9, 9, 9, 9).scale(SCALE),
    //   sigma: SCALE * 0.01,
    // });

    // ui.render();
    passEncoder.end();
    device.queue.submit([commandEncoder.finish()]);
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
    let mat = [
      k, 0, 0, 0,
      0, k, 0, 0,
      0, 0, 1, 0,
      x, y, 0, 1,
    ];
    ui.updateZoom(mat);
  }

  const DEFAULT_SCALE = 2;
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
      const gridX = (N * p.x) / w();
      const gridY = (N * p.y) / h();
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

function measureText(
  font: MsdfFont,
  text: string,
  charCallback?: (x: number, y: number, line: number, char: MsdfChar) => void,
): MsdfTextMeasurements {
  let maxWidth = 0;
  const lineWidths: number[] = [];

  let textOffsetX = 0;
  let textOffsetY = 0;
  let line = 0;
  let printedCharCount = 0;
  let nextCharCode = text.charCodeAt(0);
  for (let i = 0; i < text.length; ++i) {
    const charCode = nextCharCode;
    nextCharCode = i < text.length - 1 ? text.charCodeAt(i + 1) : -1;

    switch (charCode) {
      case 10: // Newline
        lineWidths.push(textOffsetX);
        line++;
        maxWidth = Math.max(maxWidth, textOffsetX);
        textOffsetX = 0;
        textOffsetY -= font.lineHeight;
        break;
      case 13: // CR
        break;
      case 32: // Space
        // For spaces, advance the offset without actually adding a character.
        textOffsetX += font.getXAdvance(charCode);
        break;
      default: {
        if (charCallback) {
          charCallback(textOffsetX, textOffsetY, line, font.getChar(charCode));
        }
        textOffsetX += font.getXAdvance(charCode, nextCharCode);
        printedCharCount++;
      }
    }
  }

  lineWidths.push(textOffsetX);
  maxWidth = Math.max(maxWidth, textOffsetX);

  return {
    width: maxWidth,
    height: lineWidths.length * font.lineHeight,
    lineWidths,
    printedCharCount,
  };
}

function getCanvasSelectMode() {
  const checked = document.querySelector<HTMLInputElement>(
    'input[name="canvas-input-mode"]:checked',
  )?.value as CanvasMode | undefined;
  return checked;
}

await main();
