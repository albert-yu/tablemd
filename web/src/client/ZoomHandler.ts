type Point2D = {
  x: number;
  y: number;
};
type ZoomCallback = (args: { k: number; x: number; y: number }) => void;
type Interval = [number, number];

type ZoomHandlerOptions = {
  k?: number;
  x?: number;
  y?: number;
  scaleExtent?: Interval;
};

/**
 * Handles scroll and pan
 * Adapted from https://github.com/d3/d3-zoom/blob/c8df708b78b46553bc4a0fbf1baf4ffc10cef8bd/src/zoom.js#L234
 */
export class ZoomHandler {
  k: number;
  x: number;
  y: number;
  canvas: HTMLElement;
  private scaleExtent: Interval;

  constructor(canvas: HTMLCanvasElement, opts?: ZoomHandlerOptions) {
    this.canvas = canvas;
    this.k = opts?.k ?? 1;
    this.x = opts?.x ?? 0;
    this.y = opts?.y ?? 0;
    this.scaleExtent = opts?.scaleExtent ?? [1, 100];
  }

  addZoomListener(listener: ZoomCallback) {
    let mouse: [Point2D, Point2D] | undefined = undefined;

    this.canvas.addEventListener("wheel", (event) => {
      event.preventDefault();
      const k = Math.max(
        this.scaleExtent[0],
        Math.min(
          this.scaleExtent[1],
          this.k * Math.pow(2, defaultWheelDelta(event))
        )
      );
      const newMouse = this.getMousePoint(event);
      if (mouse && !pointsAreEqual(mouse[0], newMouse)) {
        mouse[0] = newMouse;
        mouse[1] = this.invert(newMouse);
      } else if (!mouse) {
        mouse = [newMouse, this.invert(newMouse)];
      }
      const translated = translate(k, mouse[0], mouse[1]);
      this.x = translated.x;
      this.y = translated.y;
      this.k = k;
      listener({ k, x: translated.x, y: translated.y });
    });

    let isDragging = false;
    let startX = 0;
    let startY = 0;

    this.canvas.addEventListener("mousedown", (event) => {
      isDragging = true;
      startX = event.clientX - this.x;
      startY = event.clientY - this.y;
    });

    this.canvas.addEventListener("mousemove", (event) => {
      if (!isDragging) {
        return;
      }
      this.x = event.clientX - startX;
      this.y = event.clientY - startY;
      listener({ k: this.k, x: this.x, y: this.y });
    });

    this.canvas.addEventListener("mouseup", () => {
      isDragging = false;
    });
    this.canvas.addEventListener("mouseleave", () => {
      isDragging = false;
    });
  }

  private getMousePoint(event: WheelEvent): Point2D {
    const rect = this.canvas.getBoundingClientRect();
    return {
      x: event.clientX - rect.left,
      y: event.clientY - rect.top,
    };
  }
  /**
   * Adapted from
   * https://github.com/d3/d3-zoom/blob/c8df708b78b46553bc4a0fbf1baf4ffc10cef8bd/src/transform.js#L24
   */
  private invert(p: Point2D): Point2D {
    return {
      x: (p.x - this.x) / this.k,
      y: (p.y - this.y) / this.k,
    };
  }
}

/**
 * https://github.com/d3/d3-zoom/blob/c8df708b78b46553bc4a0fbf1baf4ffc10cef8bd/src/zoom.js#L34
 */
function defaultWheelDelta(event: WheelEvent) {
  return (
    -event.deltaY *
    (event.deltaMode === 1 ? 0.05 : event.deltaMode ? 1 : 0.002) *
    (event.ctrlKey ? 10 : 1)
  );
}

function pointsAreEqual(p0: Point2D, p1: Point2D): boolean {
  return p0.x === p1.x && p0.y === p1.y;
}

/**
 * https://github.com/d3/d3-zoom/blob/c8df708b78b46553bc4a0fbf1baf4ffc10cef8bd/src/zoom.js#L146
 */
function translate(k: number, p0: Point2D, p1: Point2D): Point2D {
  const x = p0.x - p1.x * k,
    y = p0.y - p1.y * k;
  return {
    x,
    y,
  };
}
