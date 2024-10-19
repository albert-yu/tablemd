import type { Vec2 } from "./Vec2";
import type { Vec4 } from "./Vec4";
import { GridRenderer } from "./grid-renderer";
import { RectRenderer, type RectangleArgs } from "./rect-renderer";
import { UniformsProvider } from "./uniforms-provider";
import { GRID_N as N } from "./constants";

const gridPoints: [Float32Array, Float32Array] = [
  Float32Array.from({ length: N * N }).map((_, i) => (i % N) / N),
  Float32Array.from({ length: N * N }).map((_, j) => Math.floor(j / N) / N),
];

export class UIRenderer {
  private rectangleRenderer: RectRenderer;
  private gridRenderer: GridRenderer;
  private uniformsProvider: UniformsProvider;

  constructor(
    private device: GPUDevice,
    private readonly context: GPUCanvasContext,
    private colorTextureView: GPUTextureView,
  ) {
    this.uniformsProvider = new UniformsProvider(device, context);
    this.gridRenderer = new GridRenderer(
      device,
      this.uniformsProvider,
      gridPoints,
    );
    this.rectangleRenderer = new RectRenderer(device, this.uniformsProvider);
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
          view: this.colorTextureView,
          resolveTarget: this.context
            .getCurrentTexture()
            .createView({ label: "antialiased resolve target" }),
          // This is background color.
          clearValue: { r: 1, g: 1, b: 1, a: 1 },
          loadOp: "clear",
          storeOp: "store",
        },
      ],
    };
    const passEncoder = commandEncoder.beginRenderPass(renderPassDescriptor);
    // const width = this.context.canvas.width;
    // const height = this.context.canvas.height;
    // passEncoder.setViewport(0, 0, width, height, 0, 1);
    // this.uniformsProvider.updateWindowData(width, height);

    this.gridRenderer.render(passEncoder);
    this.rectangleRenderer.render(passEncoder);

    passEncoder.end();
    this.device.queue.submit([commandEncoder.finish()]);

    this.afterRender();
  }

  private afterRender() {
    this.rectangleRenderer.reset();
  }
}
