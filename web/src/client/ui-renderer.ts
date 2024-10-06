import type { Vec2 } from "./Vec2";
import type { Vec4 } from "./Vec4";
import { GridRenderer } from "./grid-renderer";
import { RectRenderer } from "./rect-renderer";
import { UniformsProvider } from "./uniforms-provider";

export class UIRenderer {
  private rectangleRenderer: RectRenderer;
  private gridRenderer: GridRenderer;
  private uniformsProvider: UniformsProvider;

  constructor(
    private device: GPUDevice,
    private readonly context: GPUCanvasContext,
    private colorTextureView: GPUTextureView,
    data: [Float32Array, Float32Array],
    width: number,
    height: number,
  ) {
    this.rectangleRenderer = new RectRenderer(device, width, height);
    this.uniformsProvider = new UniformsProvider(device, width, height, data);
    this.gridRenderer = new GridRenderer(device, this.uniformsProvider, data);
  }

  rectangle(args: {
    color: Vec4;
    position: Vec2;
    size: Vec2;
    corners: Vec4;
    sigma: number;
  }): void {
    this.rectangleRenderer.rectangle(args);
  }

  updateZoom(val: number[]) {
    this.uniformsProvider.updateZoom(val);
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

    this.gridRenderer.render(passEncoder);
    this.rectangleRenderer.render(passEncoder);

    passEncoder.end();
    this.device.queue.submit([commandEncoder.finish()]);

    this.rectangleRenderer.reset();
  }
}
