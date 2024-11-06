type Point2D = {
  x: number;
  y: number;
};
type Interval = [number, number];
type ZoomCallback = (args: { k: number; x: number; y: number }) => void;
type ClickCallback = (args: Point2D) => void;

type AddListenerArgs =
  | {
      event: "zoom";
      listener: ZoomCallback;
    }
  | {
      event: "click";
      listener: ClickCallback;
    };

export type CanvasMode = "pan" | "select";

type ZoomHandlerOptions = {
  k?: number;
  x?: number;
  y?: number;
  scaleExtent?: Interval;
  mode?: CanvasMode;
};

/**
 * Handles scroll and pan
 * Adapted from https://github.com/d3/d3-zoom/blob/c8df708b78b46553bc4a0fbf1baf4ffc10cef8bd/src/zoom.js#L234
 */
export class CanvasEventHandler {
  k: number;
  x: number;
  y: number;
  canvas: HTMLElement;
  private scaleExtent: Interval;
  mode: CanvasMode;

  constructor(canvas: HTMLCanvasElement, opts?: ZoomHandlerOptions) {
    this.canvas = canvas;
    this.k = opts?.k ?? 1;
    this.x = opts?.x ?? 0;
    this.y = opts?.y ?? 0;
    this.scaleExtent = opts?.scaleExtent ?? [1, 100];
    this.mode = opts?.mode ?? "pan";
  }

  addListener(args: AddListenerArgs): () => void {
    switch (args.event) {
      case "zoom":
        return this.addZoomListener(args.listener);
      case "click":
        return this.addClickListener(args.listener);
    }
  }

  private addClickListener(listener: ClickCallback) {
    const onClick = (e: MouseEvent) => {
      if (this.mode !== "select") {
        return;
      }
      const point = this.getMousePoint(e);
      const realPoint = this.invert(point);
      listener(realPoint);
    };
    this.canvas.addEventListener("click", onClick);
    return () => {
      this.canvas.removeEventListener("click", onClick);
    };
  }

  /**
   * Adds callback to zoom events, returns cleanup function
   */
  private addZoomListener(listener: ZoomCallback) {
    let mouse: [Point2D, Point2D] | undefined = undefined;

    const wheelListener = (event: WheelEvent) => {
      event.preventDefault();
      if (event.ctrlKey) {
        // zoom
        const k = clamp(
          this.k * Math.pow(2, zoomWheelDelta(event)),
          this.scaleExtent,
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
      } else {
        // pan with scroll
        const dirX = -event.deltaX;
        const diry = -event.deltaY;
        this.x += dirX;
        this.y += diry;
        listener({ k: this.k, x: this.x, y: this.y });
      }
    };

    let isDragging = false;
    let startX = 0;
    let startY = 0;

    const downListener = (event: MouseEvent) => {
      if (this.mode !== "pan") {
        return;
      }
      isDragging = true;
      startX = event.clientX - this.x;
      startY = event.clientY - this.y;
    };

    const moveListener = (event: MouseEvent) => {
      if (this.mode !== "pan") {
        return;
      }
      if (!isDragging) {
        return;
      }
      this.x = event.clientX - startX;
      this.y = event.clientY - startY;
      listener({ k: this.k, x: this.x, y: this.y });
    };

    const upListener = () => {
      if (this.mode !== "pan") {
        return;
      }
      isDragging = false;
    };
    const leaveListener = () => {
      if (this.mode !== "pan") {
        return;
      }
      isDragging = false;
    };

    const listenerMap = {
      wheel: wheelListener,
      mousedown: downListener,
      mousemove: moveListener,
      mouseup: upListener,
      mouseleave: leaveListener,
    } as const;
    const events = Object.keys(listenerMap);

    for (const event of events) {
      // @ts-expect-error
      this.canvas.addEventListener(event, listenerMap[event]);
    }

    return () => {
      for (const event of events) {
        // @ts-expect-error
        this.canvas.removeEventListener(event, listenerMap[event]);
      }
    };
  }

  private getMousePoint(event: MouseEvent): Point2D {
    const rect = this.canvas.getBoundingClientRect();
    return {
      x: event.clientX - rect.left,
      y: event.clientY - rect.top,
    };
  }

  /**
   * Maps the point from DOM space back
   * to canvas space
   *
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
function zoomWheelDelta(event: WheelEvent) {
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

function clamp(x: number, interval: Interval) {
  const [min, max] = interval;
  return Math.max(min, Math.min(max, x));
}
