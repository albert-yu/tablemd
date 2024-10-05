import type { Vec2 } from "./Vec2";
import type { Vec4 } from "./Vec4";
import { invariant } from "./invariant";

const width = window.innerWidth;
const height = window.innerHeight;
const SAMPLE_COUNT = 4;

// First number is the size of Rectangle struct (with padding).
// Second is in this case maximum number of allowed elements (can easily go into
// high thousands).
const RECTANGLE_BUFFER_SIZE = 16 * 1024;

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
  ) {
    const rectangleShader = `
      struct VertexInput {
        @location(0) position: vec2f,
        @builtin(instance_index) instance: u32
      };

      struct VertexOutput {
        @builtin(position) position: vec4f,
        @location(1) @interpolate(flat) instance: u32,
        @location(2) @interpolate(linear) vertex: vec2f,
      };

      struct Rectangle {
        color: vec4f,
        position: vec2f,
        _unused: f32,
        sigma: f32,
        corners: vec4f,
        size: vec2f,
        window: vec2f,
      };

      struct UniformStorage {
        rectangles: array<Rectangle>,
      };

      @group(0) @binding(0) var<storage> data: UniformStorage;

      // To be honest this is a huge overkill. I tried to find what is the least
      // correct value that still works without changing how things look and
      // funnily enough it's 3. Not 3.14, just 3. But let's keep it for the sake
      // of it.
      const pi = 3.141592653589793;

      // Adapted from https://madebyevan.com/shaders/fast-rounded-rectangle-shadows/
      fn gaussian(x: f32, sigma: f32) -> f32 {
        return exp(-(x * x) / (2 * sigma * sigma)) / (sqrt(2 * pi) * sigma);
      }

      // This approximates the error function, needed for the gaussian integral.
      fn erf(x: vec2f) -> vec2f {
        let s = sign(x);
        let a = abs(x);
        var result = 1 + (0.278393 + (0.230389 + 0.078108 * (a * a)) * a) * a;
        result = result * result;
        return s - s / (result * result);
      }

      fn selectCorner(x: f32, y: f32, c: vec4f) -> f32 {
        return mix(mix(c.x, c.y, step(0, x)), mix(c.w, c.z, step(0, x)), step(0, y));
      }

      // Return the blurred mask along the x dimension.
      fn roundedBoxShadowX(x: f32, y: f32, s: f32, corner: f32, halfSize: vec2f) -> f32 {
        let d = min(halfSize.y - corner - abs(y), 0);
        let c = halfSize.x - corner + sqrt(max(0, corner * corner - d * d));
        let integral = 0.5 + 0.5 * erf((x + vec2f(-c, c)) * (sqrt(0.5) / s));
        return integral.y - integral.x;
      }

      // Return the mask for the shadow of a box from lower to upper.
      fn roundedBoxShadow(
        lower: vec2f,
        upper: vec2f,
        point: vec2f,
        sigma: f32,
        corners: vec4f
      ) -> f32 {
        // Center everything to make the math easier.
        let center = (lower + upper) * 0.5;
        let halfSize = (upper - lower) * 0.5;
        let p = point - center;

        // The signal is only non-zero in a limited range, so don't waste samples.
        let low = p.y - halfSize.y;
        let high = p.y + halfSize.y;
        let start = clamp(-3 * sigma, low, high);
        let end = clamp(3 * sigma, low, high);

        // Accumulate samples (we can get away with surprisingly few samples).
        let step = (end - start) / 4.0;
        var y = start + step * 0.5;
        var value: f32 = 0;

        for (var i = 0; i < 4; i++) {
          let corner = selectCorner(p.x, p.y, corners);
          value
            += roundedBoxShadowX(p.x, p.y - y, sigma, corner, halfSize)
            * gaussian(y, sigma) * step;
          y += step;
        }

        return value;
      }

      @vertex
      fn vertexMain(input: VertexInput) -> VertexOutput {
        var output: VertexOutput;
        let r = data.rectangles[input.instance];
        let padding = 3 * r.sigma;
        let vertex = mix(
          r.position.xy - padding,
          r.position.xy + r.size + padding,
          input.position
        );

        output.position = vec4f(vertex / r.window * 2 - 1, 0, 1);
        output.position.y = -output.position.y;
        output.vertex = vertex;
        output.instance = input.instance;
        return output;
      }

      @fragment
      fn fragmentMain(input: VertexOutput) -> @location(0) vec4f {
        let r = data.rectangles[input.instance];
        let alpha = r.color.a * roundedBoxShadow(
          r.position.xy,
          r.position.xy + r.size,
          input.vertex,
          r.sigma,
          r.corners
        );
        return vec4f(r.color.rgb, alpha);
      }
    `;

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
    this.rectangleData[this.rectangleCount * struct + 14] = width;
    this.rectangleData[this.rectangleCount * struct + 15] = height;

    this.rectangleCount += 1;
  }

  render(): void {
    invariant(this.context, "Context does not exist.");

    const commandEncoder = this.device.createCommandEncoder({
      label: "render blurred rectangles",
    });
    const renderPass = commandEncoder.beginRenderPass({
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
    });

    this.device.queue.writeBuffer(this.rectangleBuffer, 0, this.rectangleData);

    renderPass.setViewport(
      0,
      0,
      width * window.devicePixelRatio,
      height * window.devicePixelRatio,
      0,
      1,
    );
    renderPass.setVertexBuffer(0, this.vertexBuffer);

    renderPass.setPipeline(this.rectanglePipeline);
    renderPass.setBindGroup(0, this.rectangleBindGroup);
    renderPass.draw(6, this.rectangleCount);

    renderPass.end();

    this.device.queue.submit([commandEncoder.finish()]);

    this.rectangleCount = 0;
    this.rectangleData = new Float32Array(RECTANGLE_BUFFER_SIZE);
  }
}
