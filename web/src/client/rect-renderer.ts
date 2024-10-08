import type { Vec2 } from "./Vec2";
import type { Vec4 } from "./Vec4";
import { SAMPLE_COUNT } from "./constants";
import rectangleShader from "./shaders/rectangle.wgsl";
import type { UniformsProvider } from "./uniforms-provider";

// First number is the size of Rectangle struct (with padding).
// Second is in this case maximum number of allowed elements (can easily go into
// high thousands).
const RECTANGLE_BUFFER_SIZE = 16 * 1024;

/**
 * Copied from https://codesandbox.io/p/sandbox/7qt3v6?file=%2Findex.ts%3A61%2C5-61%2C14
 */
export class RectRenderer {
  rectangleData: Float32Array = new Float32Array(RECTANGLE_BUFFER_SIZE);
  rectangleCount = 0;

  vertexBuffer: GPUBuffer;
  rectangleBuffer: GPUBuffer;
  rectangleBindGroup: GPUBindGroup;
  rectanglePipeline: GPURenderPipeline;

  constructor(
    private device: GPUDevice,
    private canvasWidth: number,
    private canvasHeight: number,
    private uniforms: UniformsProvider,
  ) {
    const rectangleModule = device.createShaderModule({
      code: rectangleShader,
    });

    const uniformsLayout = this.uniforms.getBindGroupLayout();
    this.vertexBuffer = device.createBuffer({
      label: "vertex",
      // Just two triangles.
      size: 2 * 2 * 3 * Float32Array.BYTES_PER_ELEMENT,
      usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
    });

    this.rectangleBuffer = device.createBuffer({
      label: "rectangle",
      size: RECTANGLE_BUFFER_SIZE * Float32Array.BYTES_PER_ELEMENT,
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    });

    const rectangleBindGroupLayout = device.createBindGroupLayout({
      label: "rectangle bind group layout",
      entries: [
        {
          binding: 0,
          visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT,
          buffer: { type: "read-only-storage" },
        },
      ],
    });

    const rectanglePipelineLayout = device.createPipelineLayout({
      label: "rectangle pipeline layout",
      bindGroupLayouts: [rectangleBindGroupLayout, uniformsLayout],
    });

    this.rectangleBindGroup = device.createBindGroup({
      label: "rectangles",
      layout: rectangleBindGroupLayout,
      entries: [
        {
          binding: 0,
          resource: { buffer: this.rectangleBuffer },
        },
      ],
    });

    this.rectanglePipeline = device.createRenderPipeline({
      label: "blurred rectangles",
      layout: rectanglePipelineLayout,
      vertex: {
        module: rectangleModule,
        entryPoint: "vertexMain",
        buffers: [
          {
            arrayStride: 2 * Float32Array.BYTES_PER_ELEMENT,
            attributes: [
              {
                shaderLocation: 0,
                offset: 0,
                format: "float32x2",
              },
            ],
          },
        ],
      },
      fragment: {
        module: rectangleModule,
        entryPoint: "fragmentMain",
        targets: [
          {
            format: navigator.gpu.getPreferredCanvasFormat(),
            blend: {
              color: {
                srcFactor: "src-alpha",
                dstFactor: "one-minus-src-alpha",
              },
              alpha: {
                srcFactor: "src-alpha",
                dstFactor: "one-minus-src-alpha",
              },
            },
          },
        ],
      },
      multisample: { count: SAMPLE_COUNT },
    });

    // Just regular full-screen quad consisting of two triangles.
    // prettier-ignore
    const vertices = [
      0, 0,
      1, 0,
      0, 1,
      1, 0,
      0, 1,
      1, 1
    ];

    device.queue.writeBuffer(this.vertexBuffer, 0, new Float32Array(vertices));
  }

  rectangle(args: {
    color: Vec4;
    position: Vec2;
    size: Vec2;
    corners: Vec4;
    sigma: number;
  }): void {
    const { color, position, size, corners, sigma } = args;
    const struct = 16;
    this.rectangleData[this.rectangleCount * struct + 0] = color.x;
    this.rectangleData[this.rectangleCount * struct + 1] = color.y;
    this.rectangleData[this.rectangleCount * struct + 2] = color.z;
    this.rectangleData[this.rectangleCount * struct + 3] = color.w;
    this.rectangleData[this.rectangleCount * struct + 4] = position.x;
    this.rectangleData[this.rectangleCount * struct + 5] = position.y;
    this.rectangleData[this.rectangleCount * struct + 6] = 0;
    this.rectangleData[this.rectangleCount * struct + 7] = sigma;
    this.rectangleData[this.rectangleCount * struct + 8] = corners.x;
    this.rectangleData[this.rectangleCount * struct + 9] = corners.y;
    this.rectangleData[this.rectangleCount * struct + 10] = corners.z;
    this.rectangleData[this.rectangleCount * struct + 11] = corners.w;
    this.rectangleData[this.rectangleCount * struct + 12] = size.x;
    this.rectangleData[this.rectangleCount * struct + 13] = size.y;
    this.rectangleData[this.rectangleCount * struct + 14] = this.canvasWidth;
    this.rectangleData[this.rectangleCount * struct + 15] = this.canvasHeight;

    this.rectangleCount += 1;
  }

  render(passEncoder: GPURenderPassEncoder): void {
    this.device.queue.writeBuffer(this.rectangleBuffer, 0, this.rectangleData);
    passEncoder.setVertexBuffer(0, this.vertexBuffer);

    passEncoder.setPipeline(this.rectanglePipeline);
    passEncoder.setBindGroup(0, this.rectangleBindGroup);
    passEncoder.draw(6, this.rectangleCount);
  }

  reset() {
    this.rectangleCount = 0;
    this.rectangleData = new Float32Array(RECTANGLE_BUFFER_SIZE);
  }
}
