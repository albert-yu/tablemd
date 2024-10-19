type Interval = [number, number];

type ScaleDomainAndRange = {
  domain: Interval;
  range: Interval;
};
type Scales = {
  x: ScaleDomainAndRange;
  y: ScaleDomainAndRange;
};

export class UniformsProvider {
  private uniforms: Float32Array;
  private zoom: Float32Array;
  private windowScale: Float32Array;
  private untransform: Float32Array;
  private buffer: GPUBuffer;
  private layout: GPUBindGroupLayout;
  private device: GPUDevice;
  private bindGroup: GPUBindGroup;

  constructor(
    device: GPUDevice,
    private readonly context: GPUCanvasContext,
  ) {
    this.device = device;
    const uniforms = new Float32Array(50);
    this.uniforms = uniforms;
    this.zoom = uniforms.subarray(0, 16);
    this.windowScale = uniforms.subarray(16, 32);
    this.untransform = uniforms.subarray(32, 48);
    this.buffer = device.createBuffer({
      size: uniforms.byteLength,
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    });
    this.layout = device.createBindGroupLayout({
      entries: [
        {
          binding: 0,
          visibility: GPUShaderStage.VERTEX,
          buffer: { type: "uniform" },
        },
      ],
    });
    this.bindGroup = device.createBindGroup({
      layout: this.layout,
      entries: [{ binding: 0, resource: { buffer: this.buffer } }],
    });
    this.updateWindowData();
  }

  private setWindowScale(val: number[]) {
    this.windowScale.set(val);
  }

  private setUntransform(val: number[]) {
    this.untransform.set(val);
  }

  updateZoom(val: number[]) {
    this.zoom.set(val);
    this.device.queue.writeBuffer(this.buffer, 0, this.uniforms);
  }

  /**
   * Call before render
   */
  updateWindowData() {
    const w = this.context.canvas.width;
    const h = this.context.canvas.height;
    const scales: Scales = {
      x: {
        domain: [0, 1],
        range: [0, w],
      },
      y: {
        domain: [0, 1],
        range: [0, h],
      },
    };
    {
      const mats = window_transform(scales, w, h);
      this.setWindowScale(mats[0]);
      this.setUntransform(mats[1]);
    }
  }

  getBindGroupLayout() {
    return this.layout;
  }

  getBindGroup() {
    return this.bindGroup;
  }
}

function window_transform(scales: Scales, width: number, height: number) {
  // A function that creates the two matrices a webgl shader needs, in addition to the zoom state,
  // to stay aligned with canvas and d3 zoom.

  // width and height are svg parameters; x and y scales project from the data x and y into the
  // the webgl space.

  // Given two d3 scales in coordinate space, create two matrices that project from the original
  // space into [-1, 1] webgl space.

  // return the magnitude of a scale.
  const x_domain = scales.x.domain;
  const y_domain = scales.y.domain;
  const x_range = scales.x.range;
  const y_range = scales.y.range;
  let x_domain_mid = mean(x_domain);
  let y_domain_mid = mean(y_domain);
  const x_range_mid = mean(x_range);
  const y_range_mid = mean(y_range);
  let xmulti = gap(x_range) / gap(x_domain);
  let ymulti = gap(y_range) / gap(y_domain);

  // translates from data space to scaled space.
  // prettier-ignore
  const m1 = [
    xmulti, 0, 0, 0,
    0, ymulti, 0, 0,
    0, 0, 1, 0,
    -xmulti * x_domain_mid + x_range_mid,
    -ymulti * y_domain_mid + y_range_mid,
    0,
    1,
  ];

  // translate from scaled space to webgl space.
  // The '2' here is because webgl space runs from -1 to 1; the shift at the end is to
  // shift from [0, 2] to [-1, 1]
  // prettier-ignore
  const m2 = [
    2 / width, 0, 0, 0, // First column
    0, -2 / height, 0, 0, // Second column
    0, 0, 1, 0, // Third column (unchanged for z-axis in 2D transformations)
    -1, 1, 0, 1, // Fourth column, with translations adjusted for WebGL space
  ];

  return [m1, m2];
}

function mean([low, hi]: Interval) {
  return (hi - low) / 2;
}

function gap(arr: Interval) {
  return arr[1] - arr[0];
}
