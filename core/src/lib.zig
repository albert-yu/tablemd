const std = @import("std");
const engine = @import("engine.zig");
const rect = @import("render/rect.zig");

const Sheet = engine.Sheet;

/// Don't use directly, use consoleLog instead
extern fn print(ptr: [*]const u8, len: u32) void;

extern fn print_u32(value: u32) void;

extern fn print_float(value: f32) void;

/// Wrapper around `print` to make it easier to use
fn consoleLog(str: []const u8) void {
    print(str.ptr, str.len);
}

const CellPosition = struct {
    row: u32,
    col: u32,
};

const CellDimensions = struct {
    width: f32,
    height: f32,
};

const DEFAULT_SIGMA = 1e-6;
const GRID_N = 1000;
const GRID_DENSITY: comptime_float = 1.0 / 32.0;

const Point2D = struct {
    x: f32,
    y: f32,
};

/// Represents the running application
const App = struct {
    sheets: []Sheet,
    allocator: std.mem.Allocator,
    canvas_width: usize,
    canvas_height: usize,
    current_cell: ?CellPosition,
    rects: rect.Renderer,
    grid_x: []f32,
    grid_y: []f32,

    pub fn init(allocator: std.mem.Allocator, canvas_width: usize, canvas_height: usize, sheet_count: usize) !App {
        const sheets = try allocator.alloc(Sheet, sheet_count);
        errdefer allocator.free(sheets);
        const grid_x = try createXArray(allocator);
        const grid_y = try createYArray(allocator);
        errdefer allocator.free(grid_x);
        errdefer allocator.free(grid_y);
        const rects = try rect.Renderer.init(allocator);

        return App{
            .canvas_width = canvas_width,
            .canvas_height = canvas_height,
            .sheets = sheets,
            .allocator = allocator,
            .current_cell = null,
            .grid_x = grid_x,
            .grid_y = grid_y,
            .rects = rects,
        };
    }

    pub fn deinit(self: App) void {
        self.allocator.free(self.sheets);
        self.allocator.free(self.grid_x);
        self.allocator.free(self.grid_y);
        self.rects.deinit(self.allocator);
    }

    pub fn getAllocator(self: App) std.mem.Allocator {
        return self.allocator;
    }

    pub fn setCanvasSize(self: *App, width: usize, height: usize) void {
        self.canvas_width = width;
        self.canvas_height = height;
    }

    pub fn onHover(self: *App, p: Point2D) void {
        const normalizedPoint = self.normalizePoint(p);
        const cell = self.getCellPosition(normalizedPoint);
        print_u32(cell.row);
        // TODO: update cell width and height based on underlying content
        // e.g. text, cell size
        const cell_dims = self.cellDimensions();
        self.rects.hover_rect.x = cell_dims.width * @as(f32, @floatFromInt(cell.col));
        self.rects.hover_rect.y = cell_dims.height * @as(f32, @floatFromInt(cell.row));
    }

    fn normalizePoint(self: *App, canvasPoint: Point2D) Point2D {
        const maxWidth = self.canvas_width;
        const maxHeight = self.canvas_height;
        const maxGridDim = @as(f32, @floatFromInt(@min(maxWidth, maxHeight)));
        const gridX = canvasPoint.x / maxGridDim;
        const gridY = canvasPoint.y / maxGridDim;
        return Point2D{
            .x = gridX,
            .y = gridY,
        };
    }

    fn updateCurrentCell(self: *App, cell: ?CellPosition) void {
        self.current_cell = cell;
    }

    fn cellDimensions(self: App) CellDimensions {
        const width = self.grid_x[1] - self.grid_x[0];
        return CellDimensions{
            .width = width,
            .height = width,
        };
    }

    fn getCellPosition(self: App, normalizedPoint: Point2D) CellPosition {
        const x = self.getIndexOfMaxGridPointBoundedBy(normalizedPoint.x);
        const y = self.getIndexOfMaxGridPointBoundedBy(normalizedPoint.y);
        return CellPosition{
            .row = y,
            .col = x,
        };
    }

    fn getIndexOfMaxGridPointBoundedBy(self: App, upperBound: f32) u32 {
        var i: u32 = 0;
        while (i < GRID_N) : (i += 1) {
            const val = self.grid_x[i];
            if (val > upperBound) {
                i -= 1;
                break;
            }
        }
        return i;
    }
};

/// Returns null if failed to allocate
export fn app_init(canvas_width: usize, canvas_height: usize, sheet_count: usize) ?*App {
    const allocator = std.heap.wasm_allocator;
    const app = App.init(allocator, canvas_width, canvas_height, sheet_count) catch {
        return null;
    };
    const allocated_app = allocator.create(App) catch {
        app.deinit();
        return null;
    };
    allocated_app.* = app;
    consoleLog("App initialized");
    return allocated_app;
}

export fn app_deinit(app: *App) void {
    const allocator = app.getAllocator();
    app.deinit();
    allocator.destroy(app);
    consoleLog("App freed");
}

export fn app_set_canvas_size(app: *App, width: usize, height: usize) void {
    app.setCanvasSize(width, height);
}

export fn app_on_hover(app: *App, x: f32, y: f32) void {
    app.onHover(Point2D{ .x = x, .y = y });
}

fn createXArray(allocator: std.mem.Allocator) ![]f32 {
    const array = try allocator.alloc(f32, GRID_N * GRID_N);
    var i: usize = 0;
    while (i < GRID_N * GRID_N) : (i += 1) {
        const numer = @as(f32, @floatFromInt(i % GRID_N));
        const denom = GRID_N * GRID_DENSITY;
        array[i] = numer / denom;
    }
    return array;
}

fn createYArray(allocator: std.mem.Allocator) ![]f32 {
    const array = try allocator.alloc(f32, GRID_N * GRID_N);
    var i: usize = 0;
    while (i < GRID_N * GRID_N) : (i += 1) {
        const numer = @as(f32, @floatFromInt(i / GRID_N));
        const denom = GRID_N * GRID_DENSITY;
        array[i] = numer / denom;
    }
    return array;
}

fn setDword(buffer: []u8, idx: usize, dword: u32) void {
    const alpha: u8 = @truncate(dword & 0xff);
    const blue: u8 = @truncate((dword >> 8) & 0xff);
    const green: u8 = @truncate((dword >> 16) & 0xff);
    const red: u8 = @truncate((dword >> 24) & 0xff);
    buffer[idx] = red;
    buffer[idx + 1] = green;
    buffer[idx + 2] = blue;
    buffer[idx + 3] = alpha;
}
