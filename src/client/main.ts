import * as PIXI from "pixi.js";

interface ViewportState {
  x: number;
  y: number;
  scale: number;
}

class InfiniteCanvas {
  private app: PIXI.Application;
  private viewport: PIXI.Container;
  private dotContainer: PIXI.Container;
  private canvas: HTMLCanvasElement;

  private viewportState: ViewportState = {
    x: 0,
    y: 0,
    scale: 1,
  };

  private isDragging = false;
  private lastPointerPosition = { x: 0, y: 0 };
  private cursorPosition = { x: 0, y: 0 };

  private readonly DOT_SPACING = 50;
  private readonly DOT_SIZE = 2;
  private readonly DOT_COLOR = 0x888888;
  private readonly MIN_SCALE = 0.1;
  private readonly MAX_SCALE = 5;
  private readonly GRID_SIZE = 100; // Number of dots in each direction

  constructor(canvas: HTMLCanvasElement) {
    this.canvas = canvas;
    this.app = new PIXI.Application();
    this.viewport = new PIXI.Container();
    this.dotContainer = new PIXI.Container();

    this.init();
  }

  private async init() {
    // Initialize PIXI application
    await this.app.init({
      canvas: this.canvas,
      width: window.innerWidth,
      height: window.innerHeight,
      backgroundColor: 0xffffff,
      antialias: true,
      resolution: window.devicePixelRatio || 1,
      autoDensity: true,
    });

    // Set up containers
    this.app.stage.addChild(this.viewport);
    this.viewport.addChild(this.dotContainer);

    // Generate a large grid of dots once
    this.generateInitialDots();

    // Set up event listeners
    this.setupEventListeners();

    // Handle window resize
    window.addEventListener("resize", () => this.handleResize());

    // Apply initial transform
    this.updateViewport();
  }

  private setupEventListeners() {
    // Mouse events
    this.canvas.addEventListener("mousedown", (e) => this.handlePointerDown(e));
    this.canvas.addEventListener("mousemove", (e) => this.handlePointerMove(e));
    this.canvas.addEventListener("mouseup", (e) => this.handlePointerUp(e));
    this.canvas.addEventListener("mouseleave", (e) => this.handlePointerUp(e));

    // Touch events for mobile
    this.canvas.addEventListener("touchstart", (e) => this.handleTouchStart(e));
    this.canvas.addEventListener("touchmove", (e) => this.handleTouchMove(e));
    this.canvas.addEventListener("touchend", (e) => this.handleTouchEnd(e));

    // Wheel events for zooming and trackpad scrolling
    this.canvas.addEventListener("wheel", (e) => this.handleWheel(e), {
      passive: false,
    });

    // Prevent context menu
    this.canvas.addEventListener("contextmenu", (e) => e.preventDefault());
  }

  private handlePointerDown(e: MouseEvent) {
    if (e.button === 0) {
      // Left mouse button
      this.isDragging = true;
      this.updateCursorPosition(e);
      this.lastPointerPosition = { x: e.clientX, y: e.clientY };
      this.canvas.style.cursor = "grabbing";
    }
  }

  private handlePointerMove(e: MouseEvent) {
    this.updateCursorPosition(e);

    if (this.isDragging) {
      const deltaX = e.clientX - this.lastPointerPosition.x;
      const deltaY = e.clientY - this.lastPointerPosition.y;

      this.pan(deltaX, deltaY);
      this.lastPointerPosition = { x: e.clientX, y: e.clientY };
    }
  }

  private handlePointerUp(e: MouseEvent) {
    this.isDragging = false;
    this.canvas.style.cursor = "grab";
  }

  private handleTouchStart(e: TouchEvent) {
    e.preventDefault();
    if (e.touches.length === 1) {
      const touch = e.touches[0];
      this.isDragging = true;
      this.lastPointerPosition = { x: touch.clientX, y: touch.clientY };
      this.updateCursorPositionFromTouch(touch);
    }
  }

  private handleTouchMove(e: TouchEvent) {
    e.preventDefault();
    if (e.touches.length === 1 && this.isDragging) {
      const touch = e.touches[0];
      const deltaX = touch.clientX - this.lastPointerPosition.x;
      const deltaY = touch.clientY - this.lastPointerPosition.y;

      this.pan(deltaX, deltaY);
      this.lastPointerPosition = { x: touch.clientX, y: touch.clientY };
      this.updateCursorPositionFromTouch(touch);
    }
  }

  private handleTouchEnd(e: TouchEvent) {
    e.preventDefault();
    this.isDragging = false;
  }

  private handleWheel(e: WheelEvent) {
    e.preventDefault();
    this.updateCursorPosition(e);

    if (e.ctrlKey || e.metaKey) {
      // Zooming with Ctrl+scroll or trackpad pinch
      const zoomFactor = e.deltaY > 0 ? 0.9 : 1.1;
      this.zoom(zoomFactor, this.cursorPosition.x, this.cursorPosition.y);
    } else {
      // Panning with regular scroll or trackpad scroll
      this.pan(-e.deltaX, -e.deltaY);
    }
  }

  private updateCursorPosition(e: MouseEvent | WheelEvent) {
    const rect = this.canvas.getBoundingClientRect();
    this.cursorPosition = {
      x: e.clientX - rect.left,
      y: e.clientY - rect.top,
    };
  }

  private updateCursorPositionFromTouch(touch: Touch) {
    const rect = this.canvas.getBoundingClientRect();
    this.cursorPosition = {
      x: touch.clientX - rect.left,
      y: touch.clientY - rect.top,
    };
  }

  private pan(deltaX: number, deltaY: number) {
    this.viewportState.x += deltaX;
    this.viewportState.y += deltaY;
    this.updateViewport();
  }

  private zoom(factor: number, originX: number, originY: number) {
    const newScale = Math.max(
      this.MIN_SCALE,
      Math.min(this.MAX_SCALE, this.viewportState.scale * factor),
    );

    if (newScale !== this.viewportState.scale) {
      // Calculate zoom origin in world coordinates
      const worldX =
        (originX - this.viewportState.x) / this.viewportState.scale;
      const worldY =
        (originY - this.viewportState.y) / this.viewportState.scale;

      // Update scale
      this.viewportState.scale = newScale;

      // Adjust viewport position to maintain zoom origin
      this.viewportState.x = originX - worldX * this.viewportState.scale;
      this.viewportState.y = originY - worldY * this.viewportState.scale;

      this.updateViewport();
    }
  }

  private updateViewport() {
    this.viewport.position.set(this.viewportState.x, this.viewportState.y);
    this.viewport.scale.set(this.viewportState.scale);
  }

  private generateInitialDots() {
    // Generate a large grid of dots that will be transformed
    const halfGrid = this.GRID_SIZE / 2;

    for (let x = -halfGrid; x <= halfGrid; x++) {
      for (let y = -halfGrid; y <= halfGrid; y++) {
        const dot = new PIXI.Graphics();
        dot.circle(0, 0, this.DOT_SIZE);
        dot.fill(this.DOT_COLOR);
        dot.position.set(x * this.DOT_SPACING, y * this.DOT_SPACING);
        this.dotContainer.addChild(dot);
      }
    }
  }

  private handleResize() {
    this.app.renderer.resize(window.innerWidth, window.innerHeight);
  }

  public destroy() {
    window.removeEventListener("resize", () => this.handleResize());
    this.app.destroy();
  }
}

async function main() {
  // Set up the canvas
  const canvas = document.querySelector("canvas")!;
  canvas.style.cursor = "grab";

  // Create infinite canvas
  const infiniteCanvas = new InfiniteCanvas(canvas);

  // Handle cleanup on page unload
  window.addEventListener("beforeunload", () => {
    infiniteCanvas.destroy();
  });
}

await main();
