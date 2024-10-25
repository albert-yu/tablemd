import quadWGSL from "./shaders/quad.wgsl";
import { DEPTH_STENCIL_TEXTURE_FORMAT, SAMPLE_COUNT } from "./constants";
import type { UniformsProvider } from "./uniforms-provider";

export class GridRenderer {
  private gridPipeline: GPURenderPipeline;
  private xyGroup: GPUBindGroup;
  private uGroup: GPUBindGroup;
  constructor(
    device: GPUDevice,
    private uniforms: UniformsProvider,
    private gridPoints: [Float32Array, Float32Array],
  ) {
    const [xbuf, ybuf] = gridPoints.map((arr) => {
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

    const ulayout = this.uniforms.getBindGroupLayout();
    const quadModule = device.createShaderModule({
      code: quadWGSL,
    });

    this.gridPipeline = device.createRenderPipeline({
      label: "Grid render pipeline",
      layout: device.createPipelineLayout({
        bindGroupLayouts: [xyLayout, ulayout],
      }),
      vertex: {
        module: quadModule,
        entryPoint: "vert",
      },
      fragment: {
        module: quadModule,
        targets: [
          {
            format: navigator.gpu.getPreferredCanvasFormat(),
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
      multisample: { count: SAMPLE_COUNT },
      primitive: {
        topology: "triangle-list",
      },
      depthStencil: {
        depthWriteEnabled: false,
        depthCompare: "less-equal",
        format: DEPTH_STENCIL_TEXTURE_FORMAT,
      },
    });

    this.xyGroup = device.createBindGroup({
      layout: xyLayout,
      entries: [
        { binding: 0, resource: { buffer: xbuf } },
        { binding: 1, resource: { buffer: ybuf } },
      ],
    });
    this.uGroup = this.uniforms.getBindGroup();
  }

  render(passEncoder: GPURenderPassEncoder) {
    passEncoder.setPipeline(this.gridPipeline);
    passEncoder.setBindGroup(0, this.xyGroup);
    passEncoder.setBindGroup(1, this.uGroup);
    passEncoder.draw(6, this.gridPoints[0].length);
  }
}
