import { DotGridRenderer } from "./dot-grid-renderer";
import { RectRenderer } from "./rect-renderer";
import { UniformsProvider } from "./uniforms-provider";
import {
  DEPTH_STENCIL_TEXTURE_FORMAT,
  GRID_DENSITY,
  GRID_N as N,
  SAMPLE_COUNT,
} from "./constants";
import { TextRenderer } from "./text-renderer";
import type { Point2D } from "./canvas-events";

/**
 * Row-major grid points, so
 * ```
 * 0: [0, 1, 2, 3, 4, ...]
 * 1: [0, 0, 0, 0, 0, ...]
 * ```
 * to represent
 * ```
 * (0, 0), (1, 0), (2, 0), ..., (N-1, 0),
 * (0, 1), (1, 1), ...
 * ```
 */
const gridPoints: [Float32Array, Float32Array] = [
  Float32Array.from({ length: N * N }).map(
    (_, i) => (i % N) / (N * GRID_DENSITY),
  ),
  Float32Array.from({ length: N * N }).map(
    (_, j) => Math.floor(j / N) / (N * GRID_DENSITY),
  ),
];

export const GRID_CELL_HEIGHT = gridPoints[0][1] - gridPoints[0][0];
export const GRID_CELL_WIDTH = GRID_CELL_HEIGHT;

export type CellPoint = {
  /**
   * Index of row in grid, starts at 0 at top
   */
  row: number;
  /**
   * Index of column in grid
   */
  col: number;
};

export const cellPointsEqual = (a: CellPoint, b: CellPoint): boolean => {
  return a.row === b.row && a.col === b.col;
};

const BG_COLOR = { r: 37 / 256, g: 38 / 256, b: 56 / 256, a: 1 };

/**
 * @param upperBound
 * @returns index of largest grid point less than `upperBound`
 */
const getIndexOfMaxGridPointBoundedBy = (upperBound: number): number => {
  let i = 0;
  for (; i < N; i++) {
    const val = gridPoints[0][i];
    if (val > upperBound) {
      i--;
      break;
    }
  }
  return i;
};

const getGridPointXY = (x: number, y: number): Point2D => {
  const perRow = N;
  const i = perRow * y + x;
  return { x: gridPoints[0][i], y: gridPoints[1][i] };
};

/**
 * @param row index of cell row
 * @param col index of cell column
 * @returns
 */
const getRectCorners = ({ row, col }: CellPoint) => {
  const topLeft = getGridPointXY(col, row);
  const topRight = getGridPointXY(col + 1, row);
  const bottomLeft = getGridPointXY(col, row + 1);
  const bottomRight = getGridPointXY(col + 1, row + 1);
  return {
    tl: topLeft,
    tr: topRight,
    bl: bottomLeft,
    br: bottomRight,
  };
};

export class UIRenderer {
  public rects: RectRenderer;
  public texts: TextRenderer;
  private gridRenderer: DotGridRenderer;
  private uniformsProvider: UniformsProvider;
  private colorTexture: GPUTexture;
  private depthTexture: GPUTexture;
  private canvasDimensions: {
    w: number;
    h: number;
  };

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
    this.depthTexture = device.createTexture({
      size: [context.canvas.width, context.canvas.height],
      format: DEPTH_STENCIL_TEXTURE_FORMAT,
      usage: GPUTextureUsage.RENDER_ATTACHMENT,
      sampleCount: SAMPLE_COUNT,
    });

    this.uniformsProvider = new UniformsProvider(device, context);
    this.gridRenderer = new DotGridRenderer(
      device,
      this.uniformsProvider,
      gridPoints,
    );
    this.rects = new RectRenderer(device, this.uniformsProvider);
    this.texts = new TextRenderer(device, format, this.uniformsProvider);
    this.canvasDimensions = {
      w: context.canvas.width,
      h: context.canvas.height,
    };
  }

  async init() {
    await this.texts.init();
  }

  updateZoom(val: number[]) {
    this.uniformsProvider.updateZoom(val);
  }

  updateCanvasDimensions(w: number, h: number) {
    this.canvasDimensions = { w, h };
    this.uniformsProvider.updateWindowData(w, h);
  }

  normalizePoint(point: Point2D): Point2D {
    const maxWidth = this.canvasDimensions.w;
    const maxHeight = this.canvasDimensions.h;
    const maxGridDim = Math.min(maxWidth, maxHeight);
    const gridX = point.x / maxGridDim;
    const gridY = point.y / maxGridDim;
    return {
      x: gridX,
      y: gridY,
    };
  }

  getCell(point: Point2D): CellPoint {
    const { x: gridX, y: gridY } = this.normalizePoint(point);
    const x = getIndexOfMaxGridPointBoundedBy(gridX);
    const y = getIndexOfMaxGridPointBoundedBy(gridY);
    return {
      row: y,
      col: x,
    };
  }

  getCellRect(cell: CellPoint): { x: number; y: number; w: number; h: number } {
    const { tl, tr, bl } = getRectCorners(cell);
    const cellWidth = tr.x - tl.x;
    const cellHeight = bl.y - tl.y;
    return {
      x: tl.x,
      y: tl.y,
      w: cellWidth,
      h: cellHeight,
    };
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
          clearValue: BG_COLOR,
          loadOp: "clear",
          storeOp: "store",
        },
      ],
      depthStencilAttachment: {
        view: this.depthTexture.createView({ label: "depth" }),
        depthClearValue: 1.0,
        depthLoadOp: "clear",
        depthStoreOp: "store",
      },
    };
    const passEncoder = commandEncoder.beginRenderPass(renderPassDescriptor);

    this.gridRenderer.render(passEncoder);
    this.rects.render(passEncoder);
    this.texts.render(passEncoder);

    passEncoder.end();
    this.device.queue.submit([commandEncoder.finish()]);
  }

  reset() {
    this.rects.reset();
    this.texts.reset();
  }
}
