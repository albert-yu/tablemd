import { GridRenderer } from "./grid-renderer";
import { RectRenderer, type RectangleArgs } from "./rect-renderer";
import { UniformsProvider } from "./uniforms-provider";
import { DEPTH_STENCIL_FORMAT, GRID_N as N, SAMPLE_COUNT } from "./constants";
import { type MsdfFont, type MsdfText, MsdfTextRenderer } from "./msdf-text";

const gridPoints: [Float32Array, Float32Array] = [
  Float32Array.from({ length: N * N }).map((_, i) => (i % N) / N),
  Float32Array.from({ length: N * N }).map((_, j) => Math.floor(j / N) / N),
];

export class UIRenderer {
  private rectangleRenderer: RectRenderer;
  private gridRenderer: GridRenderer;
  private uniformsProvider: UniformsProvider;
  private textRenderer: MsdfTextRenderer;

  private font: MsdfFont | undefined = undefined;
  private colorTexture: GPUTexture;
  private depthTexture: GPUTexture;
  private textBlocks: MsdfText[] = [];

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
    this.uniformsProvider = new UniformsProvider(device, context);
    this.gridRenderer = new GridRenderer(
      device,
      this.uniformsProvider,
      gridPoints,
    );
    this.rectangleRenderer = new RectRenderer(device, this.uniformsProvider);
    this.depthTexture = device.createTexture({
      label: "Main - Depth texture",
      size: [context.canvas.width, context.canvas.height],
      format: DEPTH_STENCIL_FORMAT,
      usage: GPUTextureUsage.RENDER_ATTACHMENT,
      sampleCount: SAMPLE_COUNT,
    });
    this.textRenderer = new MsdfTextRenderer(
      device,
      format,
      DEPTH_STENCIL_FORMAT,
      this.uniformsProvider,
    );
  }

  async initAsync() {
    await this.fetchFont();
    if (!this.font) {
      return;
    }
    this.textBlocks.push(
      this.textRenderer.formatText(this.font, "Thing", {
        centered: true,
        pixelScale: 1 / 128,
        color: [1, 0, 0, 1],
      }),
    );
  }

  rectangle(args: RectangleArgs): void {
    this.rectangleRenderer.rectangle(args);
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
          // This is background color.
          clearValue: { r: 0, g: 0, b: 0, a: 1 },
          loadOp: "clear",
          storeOp: "store",
        },
      ],
      depthStencilAttachment: {
        view: this.depthTexture.createView({ label: "depth-stencil" }),
        depthClearValue: 1.0,
        depthLoadOp: "clear",
        depthStoreOp: "store",
      },
    };
    const passEncoder = commandEncoder.beginRenderPass(renderPassDescriptor);

    this.gridRenderer.render(passEncoder);
    this.rectangleRenderer.render(passEncoder);
    this.textRenderer.render(passEncoder, ...this.textBlocks);

    passEncoder.end();
    this.device.queue.submit([commandEncoder.finish()]);

    this.afterRender();
  }

  private afterRender() {
    this.rectangleRenderer.reset();
  }

  private async fetchFont() {
    this.font = await this.textRenderer.createFont(
      "./ascii-msdf/ascii-msdf.json",
    );
  }
}
