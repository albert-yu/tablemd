const std = @import("std");
const engine = @import("engine.zig");

const Sheet = engine.Sheet;

const float = f32;

/// Don't use directly, use consoleLog instead
extern fn print(ptr: [*]const u8, len: u32) void;

extern fn print_u32(value: u32) void;

extern fn print_float(value: float) void;

/// Wrapper around `print` to make it easier to use
fn consoleLog(str: []const u8) void {
    print(str.ptr, str.len);
}

const CellPosition = struct {
    row: u32,
    col: u32,
};

const CellDimensions = struct {
    width: float,
    height: float,
};

const DEFAULT_SIGMA: comptime_float = 1e-6;
const GRID_N = 1000;
const GRID_DENSITY: comptime_float = 1.0 / 32.0;

const Point2D = struct {
    x: float,
    y: float,
};

const RectElement = struct {
    color: [4]float,
    x: float,
    y: float,
    width: float,
    height: float,
    corners: [4]float,
    sigma: float,
};

/// Represents the running application
const App = struct {
    sheets: []Sheet,
    allocator: std.mem.Allocator,
    canvas_width: usize,
    canvas_height: usize,
    current_cell: ?CellPosition,
    hover_rect: RectElement,
    grid_x: []f32,
    grid_y: []f32,

    pub fn init(allocator: std.mem.Allocator, canvas_width: usize, canvas_height: usize, sheet_count: usize) !App {
        const sheets = try allocator.alloc(Sheet, sheet_count);
        errdefer allocator.free(sheets);
        const grid_x = try createXArray(allocator);
        const grid_y = try createYArray(allocator);
        errdefer allocator.free(grid_x);
        errdefer allocator.free(grid_y);
        const grid_cell_height = grid_x[1] - grid_x[0];
        const grid_cell_width = grid_cell_height;

        return App{
            .canvas_width = canvas_width,
            .canvas_height = canvas_height,
            .sheets = sheets,
            .allocator = allocator,
            .current_cell = null,
            .grid_x = grid_x,
            .grid_y = grid_y,
            .hover_rect = RectElement{
                .x = 0,
                .y = 0,
                .width = grid_cell_width,
                .height = grid_cell_height,
                .color = [4]float{ 0, 0, 0, 0.25 },
                .corners = [4]float{ 0, 0, 0, 0 },
                .sigma = DEFAULT_SIGMA,
            },
        };
    }

    pub fn deinit(self: App) void {
        self.allocator.free(self.sheets);
        self.allocator.free(self.grid_x);
        self.allocator.free(self.grid_y);
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
        self.hover_rect.x = cell_dims.width * @as(float, @floatFromInt(cell.col));
        self.hover_rect.y = cell_dims.height * @as(float, @floatFromInt(cell.row));
    }

    pub fn writeHoverRect(self: *App, float_array: [*c]float, offset: usize) void {
        const UNUSED = 0;
        const rect = self.hover_rect;
        float_array[offset] = rect.color[0];
        float_array[offset + 1] = rect.color[1];
        float_array[offset + 2] = rect.color[2];
        float_array[offset + 3] = rect.color[3];
        float_array[offset + 4] = rect.x;
        float_array[offset + 5] = rect.y;
        float_array[offset + 6] = UNUSED;
        float_array[offset + 7] = rect.sigma;
        float_array[offset + 8] = rect.corners[0];
        float_array[offset + 9] = rect.corners[1];
        float_array[offset + 10] = rect.corners[2];
        float_array[offset + 11] = rect.corners[3];
        float_array[offset + 12] = rect.width;
        float_array[offset + 13] = rect.height;
        float_array[offset + 14] = UNUSED;
        float_array[offset + 15] = UNUSED;
    }

    fn normalizePoint(self: *App, canvasPoint: Point2D) Point2D {
        const maxWidth = self.canvas_width;
        const maxHeight = self.canvas_height;
        const maxGridDim = @as(float, @floatFromInt(@min(maxWidth, maxHeight)));
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

    fn getIndexOfMaxGridPointBoundedBy(self: App, upperBound: float) u32 {
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

export fn app_on_hover(app: *App, x: float, y: float) void {
    app.onHover(Point2D{ .x = x, .y = y });
}

export fn app_write_hover_rect(app: *App, float_array: [*c]float, offset: usize) void {
    app.writeHoverRect(float_array, offset);
}

fn createXArray(allocator: std.mem.Allocator) ![]f32 {
    const array = try allocator.alloc(float, GRID_N * GRID_N);
    var i: usize = 0;
    print_float(GRID_DENSITY);
    while (i < GRID_N * GRID_N) : (i += 1) {
        const numer = @as(float, @floatFromInt(i % GRID_N));
        const denom = @as(float, @floatFromInt(GRID_N)) * @as(float, GRID_DENSITY);
        array[i] = numer / denom;
    }
    return array;
}

fn createYArray(allocator: std.mem.Allocator) ![]f32 {
    const array = try allocator.alloc(float, GRID_N * GRID_N);
    var i: usize = 0;
    while (i < GRID_N * GRID_N) : (i += 1) {
        const numer = @as(float, @floatFromInt(i / GRID_N));
        const denom = @as(float, @floatFromInt(GRID_N)) * @as(float, GRID_DENSITY);
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
