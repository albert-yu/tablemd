import { DotGridRenderer } from "./dot-grid-renderer";
import { RectRenderer, type RectangleArgs } from "./rect-renderer";
import { UniformsProvider } from "./uniforms-provider";
import {
  DEPTH_STENCIL_TEXTURE_FORMAT,
  GRID_DENSITY,
  GRID_N as N,
  SAMPLE_COUNT,
} from "./constants";
import {
  TextRenderer,
  type PushTextArgs,
  type UpdateTextArgs,
} from "./text-renderer";

const gridPoints: [Float32Array, Float32Array] = [
  Float32Array.from({ length: N * N }).map(
    (_, i) => (i % N) / (N * GRID_DENSITY),
  ),
  Float32Array.from({ length: N * N }).map(
    (_, j) => Math.floor(j / N) / (N * GRID_DENSITY),
  ),
];

const BG_COLOR = { r: 37 / 256, g: 38 / 256, b: 56 / 256, a: 1 };

export class UIRenderer {
  private rectangleRenderer: RectRenderer;
  private gridRenderer: DotGridRenderer;
  private uniformsProvider: UniformsProvider;
  private textRenderer: TextRenderer;
  private colorTexture: GPUTexture;
  private depthTexture: GPUTexture;

  constructor(
    private device: GPUDevice,
    private readonly context: GPUCanvasContext,
    format: GPUTextureFormat,
  ) {
    this.colorTexture = device.createTexture({
      label: "color",
      size: { width: context.canvas.width, height: context.canvas.height },
      sampleCount: SAMPLE_COUNT,
      format: format,
      usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.COPY_SRC,
    });
    this.depthTexture = device.createTexture({
      size: [context.canvas.width, context.canvas.height],
      format: DEPTH_STENCIL_TEXTURE_FORMAT,
      usage: GPUTextureUsage.RENDER_ATTACHMENT,
      sampleCount: SAMPLE_COUNT,
    });

    this.uniformsProvider = new UniformsProvider(device, context);
    this.gridRenderer = new DotGridRenderer(
      device,
      this.uniformsProvider,
      gridPoints,
    );
    this.rectangleRenderer = new RectRenderer(device, this.uniformsProvider);
    this.textRenderer = new TextRenderer(device, format, this.uniformsProvider);
  }

  async init() {
    await this.textRenderer.init();
  }

  rectangle(args: RectangleArgs): void {
    this.rectangleRenderer.rectangle(args);
  }

  pushText(args: PushTextArgs) {
    return this.textRenderer.pushText(args);
  }

  updateText(args: UpdateTextArgs): void {
    this.textRenderer.updateText(args);
  }

  updateZoom(val: number[]) {
    this.uniformsProvider.updateZoom(val);
  }

  updateCanvasDimensions(w: number, h: number) {
    this.uniformsProvider.updateWindowData(w, h);
  }

  render(): void {
    const commandEncoder = this.device.createCommandEncoder({
      label: "command encoder",
    });
    const renderPassDescriptor: GPURenderPassDescriptor = {
      label: "main render pass",
      colorAttachments: [
        {
          view: this.colorTexture.createView({ label: "color" }),
          resolveTarget: this.context
            .getCurrentTexture()
            .createView({ label: "antialiased resolve target" }),
          clearValue: BG_COLOR,
          loadOp: "clear",
          storeOp: "store",
        },
      ],
      depthStencilAttachment: {
        view: this.depthTexture.createView({ label: "depth" }),
        depthClearValue: 1.0,
        depthLoadOp: "clear",
        depthStoreOp: "store",
      },
    };
    const passEncoder = commandEncoder.beginRenderPass(renderPassDescriptor);

    this.gridRenderer.render(passEncoder);
    this.rectangleRenderer.render(passEncoder);
    this.textRenderer.render(passEncoder);

    passEncoder.end();
    this.device.queue.submit([commandEncoder.finish()]);

    this.afterRender();
  }

  private afterRender() {
    this.rectangleRenderer.reset();
  }
}
