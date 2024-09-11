type Point2D = {
  x: number;
  y: number;
};

type ZoomCallback = (args: { k: number; x: number; y: number }) => void;

/**
 * Handles scroll and pan
 * Adapted from https://github.com/d3/d3-zoom/blob/c8df708b78b46553bc4a0fbf1baf4ffc10cef8bd/src/zoom.js#L234
 */
export class ZoomHandler {
  k: number = 1;
  x: number = 0;
  y: number = 0;
  canvas: HTMLElement;

  constructor(canvas: HTMLCanvasElement) {
    this.canvas = canvas;
  }

  addZoomListener(listener: ZoomCallback) {
    this.canvas.addEventListener("wheel", (event) => {
      event.preventDefault();

      // negative is zoom in
      const dir = Math.sign(event.deltaY);
      if (dir >= 0 && this.k <= 1) {
        return;
      }
      if (dir < 0 && this.k >= 100) {
        return;
      }
      const speed = 1.01;

      // Calculate the zoom based on the mouse position
      const newMouseX = event.clientX - this.canvas.offsetLeft;
      const newMouseY = event.clientY - this.canvas.offsetTop;

      const zoomFactor = Math.pow(speed, -dir);
      this.k *= zoomFactor;
      const factor = zoomFactor - 1;
      this.x -= factor * newMouseX * this.k;
      this.y -= factor * newMouseY * this.k;
      listener({ k: this.k, x: this.x, y: this.y });
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
  }

  /**
   * https://github.com/d3/d3-zoom/blob/c8df708b78b46553bc4a0fbf1baf4ffc10cef8bd/src/zoom.js#L146
   */
  private translate(p0: Point2D, p1: Point2D): Point2D {
    const x = p0.x - p1.x * this.k,
      y = p0.y - p1.y * this.k;
    return {
      x,
      y,
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
