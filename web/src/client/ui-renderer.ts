import { GridRenderer } from "./grid-renderer";
import { RectRenderer, type RectangleArgs } from "./rect-renderer";
import { UniformsProvider } from "./uniforms-provider";
import { GRID_N as N, SAMPLE_COUNT } from "./constants";
import { TextRenderer, type TextArgs } from "./text-renderer";

const gridPoints: [Float32Array, Float32Array] = [
  Float32Array.from({ length: N * N }).map((_, i) => (i % N) / N),
  Float32Array.from({ length: N * N }).map((_, j) => Math.floor(j / N) / N),
];

export class UIRenderer {
  private rectangleRenderer: RectRenderer;
  private gridRenderer: GridRenderer;
  private uniformsProvider: UniformsProvider;
  private textRenderer: TextRenderer;
  private colorTexture: GPUTexture;

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
    this.textRenderer = new TextRenderer(device, format, this.uniformsProvider);
  }

  async init() {
    await this.textRenderer.init();
  }

  rectangle(args: RectangleArgs): void {
    this.rectangleRenderer.rectangle(args);
  }

  text(args: TextArgs): void {
    this.textRenderer.text(args);
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
