import { vec2, vec4 } from "wgpu-matrix";
import type { Point2D } from "./canvas-events";
import {
  cellPointsEqual,
  GRID_CELL_HEIGHT,
  GRID_CELL_WIDTH,
  UIRenderer,
  type CellPosition,
} from "./ui-renderer";
import { GRID_N } from "./constants";

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
  /**
   * Index of character that the cursor is on
   */
  charIndex: number;
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

export class UI {
  private renderer: UIRenderer;
  private textElements: TextElement[] = [];
  private rectElements: CellRect[] = [];
  private hoverRect: RectElement = {
    color: [1, 1, 1, 0.25],
    x: 0,
    y: 0,
    width: 0,
    height: GRID_CELL_HEIGHT,
    corners: DEFAULT_CORNERS,
  };

  private cursor: Cursor = {
    status: "inactive",
  };
  private charWidth = 0;

  constructor(
    device: GPUDevice,
    context: GPUCanvasContext,
    format: GPUTextureFormat,
  ) {
    this.renderer = new UIRenderer(device, context, format);
  }

  cursorTextWidth(): number {
    return this.charWidth / GRID_CELL_WIDTH;
  }

  async init() {
    await this.renderer.init();
    this.charWidth = this.renderer.texts.getTextWidth("a");
  }

  reset() {
    this.renderer.reset();
  }

  updateZoom(val: number[]) {
    this.renderer.updateZoom(val);
  }

  updateCanvasDimensions(w: number, h: number) {
    this.renderer.updateCanvasDimensions(w, h);
  }

  render(): void {
    for (const textElement of this.textElements) {
      this.renderer.texts.push({
        value: textElement.value,
        position: vec2.create(
          GRID_CELL_WIDTH * textElement.start.col,
          GRID_CELL_HEIGHT * textElement.start.row,
        ),
      });
    }
    for (const rectElement of this.rectElements) {
      this.renderer.rects.push({
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
    this.renderer.rects.push(rectToRenderable(this.hoverRect));
    if (this.cursor.status !== "inactive") {
      this.renderer.rects.push(cursorToRenderable(this.cursor));
    }
    this.renderer.render();
  }

  handleHover(p: Point2D) {
    const {
      rect: { x, y, width, height },
    } = this.getCursorRect(p);
    this.hoverRect.x = x;
    this.hoverRect.y = y;
    this.hoverRect.width = width;
    this.hoverRect.height = height;
  }

  /**
   * TODO: handle mousedown instead?
   * @param p
   */
  handleClick(p: Point2D) {
    const {
      charIndex,
      textElement,
      rect: { x, y, width, height },
      cell,
    } = this.getCursorRect(p);
    if (textElement) {
      this.cursor = {
        charIndex,
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
      this.cursor = {
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
  }

  handleKeyDown(e: KeyboardEvent) {
    if (this.cursor.status === "inactive") {
      return;
    }
    switch (e.key) {
      case "Escape":
        this.cursor = {
          status: "inactive",
        };
        break;
      case "ArrowUp":
      case "ArrowDown":
      case "ArrowLeft":
      case "ArrowRight":
        e.preventDefault();
        this.handleArrowKey(e);
        break;
      case "Delete":
      case "Backspace":
        {
          if (this.cursor.status !== "text") {
            break;
          }
          const text = this.cursor.text;
          const gapEnd = this.cursor.charIndex - text.value.length;
          if (gapEnd <= 0) {
            const index = this.cursor.charIndex;
            text.value =
              text.value.slice(0, index - 1) + text.value.slice(index);
          }
          // otherwise, we don't need to do anything, since
          // there is no extra text to delete
          if (text.value.length === 0) {
            const existingTextIndex = this.textElements.findIndex((t) =>
              cellPointsEqual(t.start, text.start),
            );
            if (existingTextIndex === -1) {
              // shouldn't happen
              throw new Error("Text not found");
            }
            this.textElements.splice(existingTextIndex, 1);
          }
          const cellsToFit = this.getCellsToFitText(text.value);
          text.rect.width = cellsToFit;
          retreatTextCursor(this.cursor, this.charWidth);
        }
        break;
      default:
        this.handlePrintChar(e);
        break;
    }
  }

  private handlePrintChar(e: KeyboardEvent) {
    if (this.cursor.status === "inactive") {
      return;
    }
    const char = getCharFromEvent(e);
    const isPrintable = isPrintableChar(char);
    if (!isPrintable) {
      return;
    }
    const cell =
      this.cursor.status === "cell" ? this.cursor.cell : this.cursor.text.start;
    const charIndex = this.cursor.status === "text" ? this.cursor.charIndex : 0;
    let textElement = this.textElements.find((t) =>
      cellPointsEqual(t.start, cell),
    );
    if (textElement) {
      // TODO: more efficient text editing structure like a rope
      const gapEnd = charIndex - textElement.value.length;
      if (gapEnd > 0) {
        let gap = "";
        for (let i = 0; i < gapEnd; i++) {
          gap += " ";
        }
        textElement.value = textElement.value + gap + char;
      } else {
        textElement.value =
          textElement.value.slice(0, charIndex) +
          char +
          textElement.value.slice(charIndex, textElement.value.length);
      }
      const cellsToFit = this.getCellsToFitText(textElement.value);
      textElement.rect.width = cellsToFit;
    } else {
      // Find minimum number of cells to fit the text
      const newRect: CellRect = {
        point: cell,
        color: TEXT_BG_COLOR,
        corners: DEFAULT_CORNERS,
        width: 1,
        height: 1,
      };
      this.rectElements.push(newRect);
      textElement = {
        start: cell,
        value: char,
        rect: newRect,
      };
      this.textElements.push(textElement);
    }
    // change cursor to text cursor if not already
    if (this.cursor.status !== "text") {
      this.cursor = {
        charIndex: 0,
        status: "text",
        rect: {
          x: textElement.start.col * GRID_CELL_WIDTH,
          y: textElement.start.row * GRID_CELL_HEIGHT,
          width: this.charWidth,
          height: GRID_CELL_HEIGHT,
          color: ACTIVE_CURSOR_COLOR,
          corners: DEFAULT_CORNERS,
        },
        text: textElement,
      };
    }
    advanceTextCursor(this.cursor, this.charWidth);
  }

  private getCellsToFitText(text: string): number {
    const textWidth = this.renderer.texts.getTextWidth(text);
    // Find minimum number of cells to fit the text
    return Math.ceil(textWidth / GRID_CELL_WIDTH);
  }

  private getCursorRect(p: Point2D): {
    /**
     * -1 means not a text element
     */
    charIndex: number;
    textElement: TextElement | undefined;
    rect: Pick<RectElement, "x" | "y" | "width" | "height">;
    cell: CellPosition;
  } {
    // p is given relative to canvas dimensions.
    // Need to map it back to grid space (N x N)
    const cell = this.renderer.getCell(p);

    // see if we hit a text box
    const textElement = this.textElements.find((t) =>
      rectContainsPoint(t.rect, cell),
    );
    const width = textElement ? this.cursorTextWidth() : 1;

    let charIndex = -1;
    const position = (() => {
      if (textElement) {
        charIndex = 0;
        const { start } = textElement;
        const { x, y } = this.renderer.normalizePoint(p);
        const { col, row } = start;
        let cursorX = col * GRID_CELL_WIDTH;
        while (cursorX + this.charWidth < x) {
          cursorX += this.charWidth;
          charIndex++;
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
      charIndex,
      textElement,
      cell,
      rect: {
        x: position.x,
        y: position.y,
        width: width * GRID_CELL_WIDTH,
        height: GRID_CELL_HEIGHT,
      },
    };
  }

  /**
   * Changes the cursor position based on the key pressed
   * @param cursor
   * @param e
   * @returns
   */
  private handleArrowKey(e: KeyboardEvent): void {
    // TODO: look ahead at the next character or cell
    switch (this.cursor.status) {
      case "cell": {
        const cell = this.cursor.cell;
        const { row, col } = cell;
        switch (e.key) {
          case "ArrowUp":
            cell.row = Math.max(0, row - 1);
            break;
          case "ArrowDown":
            cell.row = Math.min(GRID_N - 1, row + 1);
            break;
          case "ArrowLeft":
            cell.col = Math.max(0, col - 1);
            break;
          case "ArrowRight":
            cell.col = Math.min(GRID_N - 1, col + 1);
            break;
        }
        break;
      }
      case "text": {
        switch (e.key) {
          case "ArrowUp":
            // TODO: handle
            break;
          case "ArrowDown":
            // TODO: handle
            break;
          case "ArrowLeft":
            retreatTextCursor(this.cursor, this.charWidth);
            break;
          case "ArrowRight":
            advanceTextCursor(this.cursor, this.charWidth);
            break;
        }
        break;
      }
      case "inactive":
        // do nothing
        break;
    }
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

function rectToRenderable(rect: RectElement) {
  return {
    color: vec4.create(...rect.color),
    position: vec2.create(rect.x, rect.y),
    size: vec2.create(rect.width, rect.height),
    corners: vec4.create(...rect.corners),
    sigma: DEFAULT_SIGMA,
  };
}

function advanceTextCursor(cursor: TextCursor, charWidth: number) {
  cursor.charIndex++;
  cursor.rect.x += charWidth;
}

function retreatTextCursor(cursor: TextCursor, charWidth: number) {
  cursor.charIndex--;
  cursor.rect.x -= charWidth;
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
