import type { Vec2, Vec4 } from "wgpu-matrix";
import { DEPTH_STENCIL_TEXTURE_FORMAT, SAMPLE_COUNT } from "./constants";
import rectangleShader from "./shaders/rectangle.wgsl";
import type { UniformsProvider } from "./uniforms-provider";

export type RectangleArgs = {
  color: Vec4;
  position: Vec2;
  size: Vec2;
  corners: Vec4;
  sigma: number;
};

// First number is the size of Rectangle struct (with padding).
// Second is in this case maximum number of allowed elements (can easily go into
// high thousands).
const RECTANGLE_BUFFER_SIZE = 16 * 1024;

const X = 0;
const Y = 1;
const Z = 2;
const W = 3;

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
      depthStencil: {
        depthWriteEnabled: false,
        depthCompare: "less",
        format: DEPTH_STENCIL_TEXTURE_FORMAT,
      },
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

  /**
   *  * Pushes a rectangle to the buffer.
   *  * Returns the index of the rectangle.
   */
  rectangle(args: RectangleArgs): number {
    const { color, position, size, corners, sigma } = args;
    const struct = 16;
    const UNUSED = 0;
    this.rectangleData[this.rectangleCount * struct + 0] = color[X];
    this.rectangleData[this.rectangleCount * struct + 1] = color[Y];
    this.rectangleData[this.rectangleCount * struct + 2] = color[Z];
    this.rectangleData[this.rectangleCount * struct + 3] = color[W];
    this.rectangleData[this.rectangleCount * struct + 4] = position[X];
    this.rectangleData[this.rectangleCount * struct + 5] = position[Y];
    this.rectangleData[this.rectangleCount * struct + 6] = UNUSED;
    this.rectangleData[this.rectangleCount * struct + 7] = sigma;
    this.rectangleData[this.rectangleCount * struct + 8] = corners[X];
    this.rectangleData[this.rectangleCount * struct + 9] = corners[Y];
    this.rectangleData[this.rectangleCount * struct + 10] = corners[Z];
    this.rectangleData[this.rectangleCount * struct + 11] = corners[W];
    this.rectangleData[this.rectangleCount * struct + 12] = size[X];
    this.rectangleData[this.rectangleCount * struct + 13] = size[Y];
    this.rectangleData[this.rectangleCount * struct + 14] = UNUSED;
    this.rectangleData[this.rectangleCount * struct + 15] = UNUSED;

    const index = this.rectangleCount;
    this.rectangleCount += 1;
    return index;
  }

  updateRect(index: number, args: Partial<RectangleArgs>): void {
    const { color, position, size, corners, sigma } = args;
    const struct = 16;
    if (color) {
      this.rectangleData[index * struct + 0] = color[X];
      this.rectangleData[index * struct + 1] = color[Y];
      this.rectangleData[index * struct + 2] = color[Z];
      this.rectangleData[index * struct + 3] = color[W];
    }
    if (position) {
      this.rectangleData[index * struct + 4] = position[X];
      this.rectangleData[index * struct + 5] = position[Y];
    }
    if (sigma) {
      this.rectangleData[index * struct + 7] = sigma;
    }
    if (corners) {
      this.rectangleData[index * struct + 8] = corners[X];
      this.rectangleData[index * struct + 9] = corners[Y];
      this.rectangleData[index * struct + 10] = corners[Z];
      this.rectangleData[index * struct + 11] = corners[W];
    }
    if (size) {
      this.rectangleData[index * struct + 12] = size[X];
      this.rectangleData[index * struct + 13] = size[Y];
    }
  }

  render(passEncoder: GPURenderPassEncoder): void {
    if (this.rectangleCount === 0) {
      return;
    }
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
