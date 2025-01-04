import { vec2, vec4 } from "wgpu-matrix";
import {
  type CanvasMode,
  type Point2D,
  CanvasEventHandler,
} from "./canvas-events";
import {
  cellPointsEqual,
  GRID_CELL_HEIGHT,
  GRID_CELL_WIDTH,
  UIRenderer,
  type CellPosition,
} from "./ui-renderer";
import { GRID_N } from "./constants";

const cursorStyle = {
  select: "auto",
  pan: "grab",
} as const;

type Color = [number, number, number, number];
type Corners = [number, number, number, number];

type CellRect = {
  point: CellPosition;
  color: Color;
  corners: Corners;
  width: number;
  height: number;
};

type TextElement = {
  start: CellPosition;
  value: string;
  rect: CellRect;
};

type RectElement = Point2D & {
  color: Color;
  corners: Corners;
  width: number;
  height: number;
};

type InactiveCursor = {
  status: "inactive";
};

type TextCursor = {
  status: "text";
  rect: RectElement;
  text: TextElement;
};

type CellCursor = {
  status: "cell";
  cell: CellPosition;
  rect: Omit<RectElement, "x" | "y">;
};

type Cursor = InactiveCursor | TextCursor | CellCursor;

const CORNER_VAL = 1 / 512;
const DEFAULT_CORNERS: Corners = [
  CORNER_VAL,
  CORNER_VAL,
  CORNER_VAL,
  CORNER_VAL,
];
const TEXT_BG_COLOR: Color = [0, 0, 0, 0.5];
const ACTIVE_CURSOR_COLOR: Color = [1, 1, 1, 0.5];
const DEFAULT_SIGMA = 1e-6;

async function main() {
  const canvas = document.querySelector("canvas")!;
  if (!navigator.gpu) {
    const errNode = document.createElement("div");
    errNode.innerHTML = `<p>WebGPU is not supported on this browser.</p>
    <p>Use Chrome, Edge, or another Chromium-based browser.</p>`;
    errNode.style.color = "red";
    canvas.replaceWith(errNode);
    console.error("WebGPU not supported on this browser.");
    return;
  }

  const adapter = await navigator.gpu.requestAdapter();
  if (!adapter) {
    throw new Error("No adapter found.");
  }

  const device = await adapter.requestDevice();
  const context = canvas.getContext("webgpu")!;
  const devicePixelRatio = window.devicePixelRatio;

  canvas.width = canvas.clientWidth * devicePixelRatio;
  canvas.height = canvas.clientHeight * devicePixelRatio;
  const format = navigator.gpu.getPreferredCanvasFormat();

  context.configure({
    device,
    format,
  });

  const w = () => canvas.clientWidth;
  const h = () => canvas.clientHeight;

  let frames = 0;

  let time = Date.now();

  const fpsSpan = document.querySelector("#fps")!;

  const ui = new UIRenderer(device, context, format);
  await ui.init();
  const charWidth = ui.texts.getTextWidth("a");
  const textCursorWidth = charWidth / GRID_CELL_WIDTH;
  // UI state start
  const textElements: TextElement[] = [];
  const rectElements: CellRect[] = [];

  const hoverRect: RectElement = {
    color: [1, 1, 1, 0.25],
    x: 0,
    y: 0,
    width: 0,
    height: GRID_CELL_HEIGHT,
    corners: DEFAULT_CORNERS,
  };

  let cursor: Cursor = {
    status: "inactive",
  };

  // UI state end

  // helper functions

  /**
   * Returns the cursor dimensions, aware of
   * text elements
   * @param p canvas-relative point
   * @returns
   */
  const getCursorRect = (
    p: Point2D,
  ): {
    textElement: TextElement | undefined;
    rect: Pick<RectElement, "x" | "y" | "width" | "height">;
    cell: CellPosition;
  } => {
    // p is given relative to canvas dimensions.
    // Need to map it back to grid space (N x N)
    const cell = ui.getCell(p);

    // see if we hit a text box
    const textElement = textElements.find((t) =>
      rectContainsPoint(t.rect, cell),
    );
    const width = textElement ? textCursorWidth : 1;

    const position = (() => {
      if (textElement) {
        const { start } = textElement;
        let { x, y } = ui.normalizePoint(p);
        let { col, row } = start;
        let cursorX = col * GRID_CELL_WIDTH;
        while (cursorX + charWidth < x) {
          cursorX += charWidth;
        }
        let cursorY = row * GRID_CELL_HEIGHT;
        while (cursorY + GRID_CELL_HEIGHT < y) {
          cursorY += GRID_CELL_HEIGHT;
        }
        return {
          x: cursorX,
          y: cursorY,
        };
      }
      return {
        x: GRID_CELL_WIDTH * cell.col,
        y: GRID_CELL_HEIGHT * cell.row,
      };
    })();

    return {
      textElement,
      cell,
      rect: {
        x: position.x,
        y: position.y,
        width: width * GRID_CELL_WIDTH,
        height: GRID_CELL_HEIGHT,
      },
    };
  };

  function frame() {
    ui.reset();
    for (const textElement of textElements) {
      ui.texts.push({
        value: textElement.value,
        position: vec2.create(
          GRID_CELL_WIDTH * textElement.start.col,
          GRID_CELL_HEIGHT * textElement.start.row,
        ),
      });
    }
    for (const rectElement of rectElements) {
      ui.rects.push({
        color: vec4.create(...rectElement.color),
        position: vec2.create(
          GRID_CELL_WIDTH * rectElement.point.col,
          GRID_CELL_HEIGHT * rectElement.point.row,
        ),
        size: vec2.create(
          GRID_CELL_WIDTH * rectElement.width,
          GRID_CELL_HEIGHT * rectElement.height,
        ),
        corners: vec4.create(...rectElement.corners),
        sigma: DEFAULT_SIGMA,
      });
    }
    // Hover rect
    ui.rects.push(rectToRenderable(hoverRect));
    if (cursor.status !== "inactive") {
      ui.rects.push(cursorToRenderable(cursor));
    }
    ui.render();

    frames++;
    const now = Date.now();
    if (now - time > 1000) {
      time = now;
      fpsSpan.innerHTML = `${frames}`;
      frames = 0;
    }
    requestAnimationFrame(frame);
  }

  requestAnimationFrame(frame);

  function zoomed({ k, x, y }: { k: number; x: number; y: number }) {
    // prettier-ignore
    const mat = [
      k, 0, 0, 0,
      0, k, 0, 0,
      0, 0, 1, 0,
      x, y, 0, 1,
    ];
    ui.updateZoom(mat);
  }

  const DEFAULT_SCALE = 1;
  let mode: CanvasMode = getCanvasSelectMode() ?? "select";
  const canvasEvents = new CanvasEventHandler(canvas, {
    k: DEFAULT_SCALE,
    mode,
  });
  canvasEvents.addListener({ event: "zoom", listener: zoomed });
  canvasEvents.addListener({
    event: "keydown",
    listener: (e) => {
      if (cursor.status === "inactive") {
        return;
      }
      let handled = true;
      // TODO: handle text cursor
      const cell = cursor.status === "cell" ? cursor.cell : cursor.text.start;
      const { row, col } = cell;
      switch (e.key) {
        case "Escape":
          cursor = {
            status: "inactive",
          };
          break;
        case "ArrowUp":
          e.preventDefault();
          cell.row = Math.max(0, row - 1);
          break;
        case "ArrowDown":
          e.preventDefault();
          cell.row = Math.min(GRID_N - 1, row + 1);
          break;
        case "ArrowLeft":
          cell.col = Math.max(0, col - 1);
          break;
        case "ArrowRight":
          cell.col = Math.min(GRID_N - 1, col + 1);
          break;
        case "Delete":
        case "Backspace":
          {
            const start = cell;
            const existingTextIndex = textElements.findIndex((t) =>
              cellPointsEqual(t.start, start),
            );
            if (existingTextIndex === -1) {
              break;
            }
            const existingText = textElements[existingTextIndex];
            existingText.value = existingText.value.slice(0, -1);
            if (existingText.value.length === 0) {
              textElements.splice(existingTextIndex, 1);
            }
            const textWidth = ui.texts.getTextWidth(existingText.value);
            // Find minimum number of cells to fit the text
            const cellsToFit = Math.ceil(textWidth / GRID_CELL_WIDTH);
            existingText.rect.width = cellsToFit;
          }
          break;
        default:
          handled = false;
          break;
      }
      if (handled) {
        return;
      }
      const char = getCharFromEvent(e);
      const isPrintable = isPrintableChar(char);
      if (!isPrintable) {
        return;
      }

      let textElement = textElements.find((t) =>
        cellPointsEqual(t.start, cell),
      );
      if (textElement) {
        textElement.value += char;
        const textWidth = ui.texts.getTextWidth(textElement.value);
        // Find minimum number of cells to fit the text
        const cellsToFit = Math.ceil(textWidth / GRID_CELL_WIDTH);
        textElement.rect.width = cellsToFit;
      } else {
        const textWidth = ui.texts.getTextWidth(char);
        const newRect: CellRect = {
          point: cell,
          color: TEXT_BG_COLOR,
          corners: DEFAULT_CORNERS,
          width: textWidth,
          height: 1,
        };
        rectElements.push(newRect);
        textElement = {
          start: cell,
          value: char,
          rect: newRect,
        };
        textElements.push(textElement);
      }
    },
  });
  canvasEvents.addListener({
    event: "click",
    listener: (p) => {
      const {
        textElement,
        rect: { x, y, width, height },
        cell,
      } = getCursorRect(p);
      if (textElement) {
        cursor = {
          status: "text",
          rect: {
            x,
            y,
            width,
            height,
            color: ACTIVE_CURSOR_COLOR,
            corners: DEFAULT_CORNERS,
          },
          text: textElement,
        };
      } else {
        cursor = {
          status: "cell",
          cell,
          rect: {
            width: width,
            height: height,
            color: ACTIVE_CURSOR_COLOR,
            corners: DEFAULT_CORNERS,
          },
        };
      }
    },
  });
  canvasEvents.addListener({
    event: "hover",
    listener: (p) => {
      const {
        rect: { x, y, width, height },
      } = getCursorRect(p);
      hoverRect.x = x;
      hoverRect.y = y;
      hoverRect.width = width;
      hoverRect.height = height;
    },
  });
  (globalThis as any)["updateMode"] = function (radio: HTMLInputElement) {
    const value = radio.value as CanvasMode;
    canvasEvents.mode = value;
    canvas.style.cursor = cursorStyle[value];
  };
  zoomed({ k: DEFAULT_SCALE, x: 0, y: 0 });
  ui.updateCanvasDimensions(canvas.clientWidth, canvas.clientHeight);

  window.addEventListener("resize", () => {
    ui.updateCanvasDimensions(canvas.clientWidth, canvas.clientHeight);
  });

  try {
    let memory: WebAssembly.Memory | undefined = undefined;
    // const ctx = canvas.getContext("2d")!;
    // canvas.height = CANVAS_HEIGHT;
    // canvas.width = CANVAS_WIDTH;
    const size = w() * h();
    const _byteSize = size * 4;

    // ctx.imageSmoothingEnabled = false;

    const response = await fetch("core.wasm");
    const bytes = await response.arrayBuffer();
    const _result = await WebAssembly.instantiate(bytes, {
      env: {
        print_u32: (x: number) => {
          console.log(x);
        },
        print: (ptr: number, len: number) => {
          const bytes = new Uint8Array(memory!.buffer, ptr, len);
          const str = new TextDecoder("utf-8").decode(bytes);
          console.log(str);
        },
      },
    });
    // const exports = result.instance.exports;
    // const initApp = exports.app_init as CallableFunction;
    // const getCanvasBufferPtr = exports.get_canvas_buffer_ptr as CallableFunction;
    // // const deinitApp = exports.app_deinit;
    // const app = initApp(CANVAS_WIDTH, CANVAS_HEIGHT, 1);
    // memory = exports.memory as WebAssembly.Memory;

    // const render = () => {
    //   const canvasBufferOffset = getCanvasBufferPtr(app);
    //   const canvasData = new Uint8ClampedArray(
    //     memory.buffer,
    //     canvasBufferOffset,
    //     byteSize,
    //   );
    //   const imageData = new ImageData(canvasData, CANVAS_WIDTH);
    //   ctx.putImageData(imageData, 0, 0);
    // };

    // const handleClickCell = (e) => {
    //   const { offsetX, offsetY } = e;
    //   exports.app_highlight_clicked_cell(app, offsetX, offsetY);
    //   render();
    // };
    // const clearGrid = () => {
    //   exports.app_clear_grid(app);
    //   render();
    // };
    // canvas.addEventListener("click", handleClickCell);
    // canvas.addEventListener("blur", clearGrid);
    // render();

    // deinitApp(app);
  } catch (err) {
    console.log(err);
  }
}

function rectContainsPoint(rect: CellRect, point: CellPosition) {
  const { row, col } = point;
  const { point: rectPoint, width, height } = rect;
  return (
    rectPoint.row <= row &&
    rectPoint.col <= col &&
    rectPoint.row + height > row &&
    rectPoint.col + width > col
  );
}

function getCanvasSelectMode() {
  const checked = document.querySelector<HTMLInputElement>(
    'input[name="canvas-input-mode"]:checked',
  )?.value as CanvasMode | undefined;
  return checked;
}

function getCharFromEvent(e: KeyboardEvent) {
  if (e.key.length !== 1) {
    // Ignore Shift, Alt, Ctrl, etc.
    return "";
  }
  if (e.shiftKey) {
    switch (e.key) {
      case "1":
        return "!";
      case "2":
        return "@";
      case "3":
        return "#";
      case "4":
        return "$";
      case "5":
        return "%";
      case "6":
        return "^";
      case "7":
        return "&";
      case "8":
        return "*";
      case "9":
        return "(";
      case "0":
        return ")";
      case "-":
        return "_";
      case "=":
        return "+";
      case "[":
        return "{";
      case "]":
        return "}";
      case "\\":
        return "|";
      case ";":
        return ":";
      case "'":
        return '"';
      case ",":
        return "<";
      case ".":
        return ">";
      case "/":
        return "?";
      default:
        return e.key;
    }
  }
  return e.key;
}

function isPrintableChar(char: string) {
  return char.match(/^[\P{Cc}\P{Cn}\P{Cs}]+$/gu);
}

function rectToRenderable(rect: RectElement) {
  return {
    color: vec4.create(...rect.color),
    position: vec2.create(rect.x, rect.y),
    size: vec2.create(rect.width, rect.height),
    corners: vec4.create(...rect.corners),
    sigma: DEFAULT_SIGMA,
  };
}

function cursorToRenderable(cursor: Cursor) {
  switch (cursor.status) {
    case "inactive":
      return {
        color: vec4.create(0, 0, 0, 0),
        position: vec2.create(0, 0),
        size: vec2.create(0, 0),
        corners: vec4.create(0, 0, 0, 0),
        sigma: DEFAULT_SIGMA,
      };
    case "cell":
      return {
        color: vec4.create(...cursor.rect.color),
        position: vec2.create(
          GRID_CELL_WIDTH * cursor.cell.col,
          GRID_CELL_HEIGHT * cursor.cell.row,
        ),
        size: vec2.create(cursor.rect.width, cursor.rect.height),
        corners: vec4.create(...cursor.rect.corners),
        sigma: DEFAULT_SIGMA,
      };
    case "text":
      return {
        color: vec4.create(...cursor.rect.color),
        position: vec2.create(cursor.rect.x, cursor.rect.y),
        size: vec2.create(cursor.rect.width, cursor.rect.height),
        corners: vec4.create(...cursor.rect.corners),
        sigma: DEFAULT_SIGMA,
      };
  }
}

await main();
