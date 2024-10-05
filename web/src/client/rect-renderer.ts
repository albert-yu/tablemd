import type { Vec2 } from "./Vec2";
import type { Vec4 } from "./Vec4";
import { SAMPLE_COUNT } from "./constants";
import rectangleShader from "./shaders/rectangle.wgsl";

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
    private readonly context: GPUCanvasContext,
    private colorTextureView: GPUTextureView,
    private width: number,
    private height: number,
  ) {
    const rectangleModule = device.createShaderModule({
      code: rectangleShader,
    });

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
      bindGroupLayouts: [rectangleBindGroupLayout],
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
    const vertices = [0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 1, 1];

    device.queue.writeBuffer(this.vertexBuffer, 0, new Float32Array(vertices));
  }

  rectangle(
    color: Vec4,
    position: Vec2,
    size: Vec2,
    corners: Vec4,
    sigma: number,
  ): void {
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
    this.rectangleData[this.rectangleCount * struct + 14] = this.width;
    this.rectangleData[this.rectangleCount * struct + 15] = this.height;

    this.rectangleCount += 1;
  }

  render(passEncoder: GPURenderPassEncoder): void {
    // const commandEncoder = this.device.createCommandEncoder({
    //   label: "render blurred rectangles",
    // });
    // const renderPass = commandEncoder.beginRenderPass({
    //   colorAttachments: [
    //     {
    //       view: this.colorTextureView,
    //       resolveTarget: this.context
    //         .getCurrentTexture()
    //         .createView({ label: "antialiased resolve target" }),
    //       // This is background color.
    //       clearValue: { r: 1, g: 1, b: 1, a: 1 },
    //       loadOp: "clear",
    //       storeOp: "store",
    //     },
    //   ],
    // });

    this.device.queue.writeBuffer(this.rectangleBuffer, 0, this.rectangleData);

    // renderPass.setViewport(
    //   0,
    //   0,
    //   this.width * window.devicePixelRatio,
    //   this.height * window.devicePixelRatio,
    //   0,
    //   1,
    // );
    passEncoder.setVertexBuffer(0, this.vertexBuffer);

    passEncoder.setPipeline(this.rectanglePipeline);
    passEncoder.setBindGroup(0, this.rectangleBindGroup);
    passEncoder.draw(6, this.rectangleCount);

    // renderPass.end();

    // this.device.queue.submit([commandEncoder.finish()]);

    this.rectangleCount = 0;
    this.rectangleData = new Float32Array(RECTANGLE_BUFFER_SIZE);
  }
}
